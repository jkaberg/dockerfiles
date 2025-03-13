#!/usr/bin/env python3
"""
TLS certificate management for the mail forwarder.
"""

import os
import logging
import subprocess
import shutil
import random
from pathlib import Path
import time
import datetime
import threading
import stat

from config import Configuration
from utils import render_template, ensure_template_exists

# Configure logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('tls_config')

# Constants
CERTS_DIR = "/etc/letsencrypt/live"
ARCHIVE_DIR = "/etc/letsencrypt/archive"
RENEWAL_DIR = "/etc/letsencrypt/renewal"
CERTBOT_CONFIG_DIR = "/etc/letsencrypt"
POSTFIX_CERT_DIR = "/etc/postfix/certs"
TEMPLATES_DIR = "/templates/tls"
RENEWAL_THRESHOLD_DAYS = 7  # Renew certificates if they expire within 7 days
HOOK_SCRIPTS_DIR = "/etc/letsencrypt/renewal-hooks/custom"
CRON_FILE = "/etc/cron.d/certbot-renewal"

def create_hook_scripts(config: Configuration = None):
    """Create script files for certbot and certificate renewal using Jinja2 templates."""
    # Ensure the hooks directory exists
    os.makedirs(HOOK_SCRIPTS_DIR, exist_ok=True)
    
    # Define the hooks and scripts
    scripts = {
        "pre-hook.sh": os.path.join(TEMPLATES_DIR, "pre-hook.sh.j2"),
        "post-hook.sh": os.path.join(TEMPLATES_DIR, "post-hook.sh.j2"),
        "renew-certificates.sh": os.path.join(TEMPLATES_DIR, "renew-certificates.sh.j2")
    }
    
    # Render each script
    for script_name, template_path in scripts.items():
        script_path = os.path.join(HOOK_SCRIPTS_DIR, script_name)
        
        # Set template variables
        template_vars = {}
        if script_name == "renew-certificates.sh":
            if config is None:
                logger.error("Config is required for rendering renew-certificates.sh")
                raise ValueError("Config parameter must be provided for renew-certificates.sh template")
            template_vars = {"config": config}
        
        # Render the template
        render_template(
            template_path,
            script_path,
            template_vars,
            None  # No service to reload
        )
        
        # Make the script executable
        os.chmod(script_path, os.stat(script_path).st_mode | stat.S_IEXEC)
        logger.info(f"Created executable script: {script_path}")
    
    return os.path.join(HOOK_SCRIPTS_DIR, "pre-hook.sh"), os.path.join(HOOK_SCRIPTS_DIR, "post-hook.sh")

def create_self_signed_cert(domain, cert_dir, key_size=2048, days_valid=365):
    """Create a self-signed certificate for the domain."""
    cert_path = os.path.join(cert_dir, f"{domain}/fullchain.pem")
    key_path = os.path.join(cert_dir, f"{domain}/privkey.pem")
    
    # Check if cert already exists
    if os.path.exists(cert_path) and os.path.exists(key_path):
        logger.info(f"Self-signed certificate for {domain} already exists")
        return cert_path, key_path
    
    # Ensure domain directory exists
    os.makedirs(os.path.join(cert_dir, domain), exist_ok=True)
    
    # Generate private key
    subprocess.run([
        "openssl", "genrsa",
        "-out", key_path,
        str(key_size)
    ], check=True)
    
    # Generate self-signed certificate
    subprocess.run([
        "openssl", "req",
        "-new",
        "-x509",
        "-key", key_path,
        "-out", cert_path,
        "-days", str(days_valid),
        "-subj", f"/CN={domain}"
    ], check=True)
    
    logger.info(f"Created self-signed certificate for {domain}")
    return cert_path, key_path

def setup_certbot_for_domain(domain, email, staging=False):
    """Set up Let's Encrypt certificate using certbot."""
    # Check if certificate already exists
    if os.path.exists(os.path.join(CERTS_DIR, domain, "fullchain.pem")) and \
       os.path.exists(os.path.join(CERTS_DIR, domain, "privkey.pem")):
        logger.info(f"Let's Encrypt certificate for {domain} already exists")
        return
    
    # Create hook scripts
    pre_hook_script, post_hook_script = create_hook_scripts()
    
    # Prepare base command
    base_cmd = [
        "certbot", "certonly",
        "--non-interactive",
        "--agree-tos",
        "--email", email,
        "--cert-name", domain,
        "-d", domain,
        "--pre-hook", pre_hook_script,
        "--post-hook", post_hook_script
    ]
    
    if staging:
        base_cmd.append("--test-cert")
    
    # Try with TLS-ALPN-01 challenge on port 587 (Submission) as primary method
    logger.info(f"Attempting to set up Let's Encrypt certificate for {domain} using TLS-ALPN-01 challenge on port 587")
    alpn_cmd = base_cmd + [
        "--preferred-challenges", "tls-alpn-01",
        "--tls-alpn-port", "587"
    ]
    
    try:
        subprocess.run(alpn_cmd, check=True)
        logger.info(f"Successfully set up Let's Encrypt certificate for {domain} using TLS-ALPN-01 challenge on port 587")
        return
    except subprocess.CalledProcessError as e:
        logger.warning(f"Failed to set up certificate using TLS-ALPN-01 on port 587: {e}")
    
    # Fall back to TLS-ALPN-01 challenge on port 465 (SMTPS)
    logger.info(f"Falling back to TLS-ALPN-01 challenge on port 465 for {domain}")
    alpn_cmd = base_cmd + [
        "--preferred-challenges", "tls-alpn-01",
        "--tls-alpn-port", "465"
    ]
    
    try:
        subprocess.run(alpn_cmd, check=True)
        logger.info(f"Successfully set up Let's Encrypt certificate for {domain} using TLS-ALPN-01 challenge on port 465")
        return
    except subprocess.CalledProcessError as e:
        logger.warning(f"Failed to set up certificate using TLS-ALPN-01 on port 465: {e}")
    
    # Fall back to HTTP-01 challenge if ALPN fails
    logger.info(f"Falling back to HTTP-01 challenge for {domain}")
    http_cmd = base_cmd + [
        "--preferred-challenges", "http-01"
    ]
    
    try:
        subprocess.run(http_cmd, check=True)
        logger.info(f"Successfully set up Let's Encrypt certificate for {domain} using HTTP-01 challenge")
        return
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to set up Let's Encrypt certificate for {domain} using all methods: {e}")
        raise

def setup_cron_job(config: Configuration):
    """Set up a cron job for certificate renewal."""
    # Create a random hour and minute for the cron job to run
    # This helps distribute the load on Let's Encrypt servers
    random_hour = random.randint(0, 23)
    random_minute = random.randint(0, 59)
    
    # Render the cron job template
    cron_template_path = os.path.join(TEMPLATES_DIR, "certbot-cron.j2")
    
    render_template(
        cron_template_path,
        CRON_FILE,
        {
            "random_hour": random_hour,
            "random_minute": random_minute
        },
        None  # No service to reload
    )
    
    # Make sure the cron file has correct permissions
    os.chmod(CRON_FILE, 0o644)
    
    logger.info(f"Created certificate renewal cron job at {CRON_FILE} (runs daily at {random_hour:02d}:{random_minute:02d})")

def check_certificate_expiry(cert_path):
    """Check if a certificate is about to expire."""
    try:
        output = subprocess.check_output([
            "openssl", "x509", 
            "-in", cert_path,
            "-noout",
            "-enddate"
        ]).decode('utf-8').strip()
        
        # Extract expiry date
        expiry_date_str = output.split('=')[1]
        expiry_date = datetime.datetime.strptime(expiry_date_str, "%b %d %H:%M:%S %Y %Z")
        
        # Calculate days until expiry
        now = datetime.datetime.now()
        days_until_expiry = (expiry_date - now).days
        
        logger.info(f"Certificate {cert_path} expires in {days_until_expiry} days")
        
        # Return True if certificate needs renewal
        return days_until_expiry <= RENEWAL_THRESHOLD_DAYS
    except Exception as e:
        logger.error(f"Error checking certificate expiry for {cert_path}: {e}")
        # If we can't check, assume renewal is needed to be safe
        return True

def configure_tls(config: Configuration):
    """Configure TLS certificates based on the provided configuration."""
    if not config.tls.enabled:
        logger.info("TLS is disabled, skipping certificate configuration")
        return
    
    logger.info("Configuring TLS certificates")
    
    # Ensure directories exist
    Path(POSTFIX_CERT_DIR).mkdir(parents=True, exist_ok=True)
    Path(HOOK_SCRIPTS_DIR).mkdir(parents=True, exist_ok=True)
    
    # Create hook scripts and renewal script
    create_hook_scripts(config)
    
    # Configure certbot renewal settings
    renewal_conf_template = os.path.join(TEMPLATES_DIR, "certbot-renewal.conf.j2")
    renewal_conf_path = os.path.join(CERTBOT_CONFIG_DIR, "renewal.conf")
    
    # Render the renewal configuration template
    render_template(
        renewal_conf_template,
        renewal_conf_path,
        {"config": config},
        None  # No service to reload
    )
    logger.info(f"Created certbot renewal configuration at {renewal_conf_path}")
    
    # Set up cron job for certificate renewal
    setup_cron_job(config)
    
    # The domains are now automatically derived from forwarding rules if not explicitly set
    for domain in config.tls.domains:
        if config.tls.use_letsencrypt:
            # Configure Let's Encrypt certificate
            setup_certbot_for_domain(domain, config.tls.email, config.tls.staging)
            
            # Link certificates to Postfix directory
            domain_cert_dir = os.path.join(POSTFIX_CERT_DIR, domain)
            os.makedirs(domain_cert_dir, exist_ok=True)
            
            # Copy or link the Let's Encrypt certificates
            cert_src = os.path.join(CERTS_DIR, domain, "fullchain.pem")
            key_src = os.path.join(CERTS_DIR, domain, "privkey.pem")
            
            if os.path.exists(cert_src) and os.path.exists(key_src):
                # Create hardlinks to the certificates
                cert_dest = os.path.join(domain_cert_dir, "fullchain.pem")
                key_dest = os.path.join(domain_cert_dir, "privkey.pem")
                
                # Remove existing files
                if os.path.exists(cert_dest):
                    os.remove(cert_dest)
                if os.path.exists(key_dest):
                    os.remove(key_dest)
                
                # Create hardlinks
                os.link(cert_src, cert_dest)
                os.link(key_src, key_dest)
                
                logger.info(f"Linked Let's Encrypt certificates for {domain}")
            else:
                logger.warning(f"Let's Encrypt certificates for {domain} not found, falling back to self-signed")
                create_self_signed_cert(domain, POSTFIX_CERT_DIR, config.tls.key_size)
        else:
            # Create self-signed certificate
            create_self_signed_cert(domain, POSTFIX_CERT_DIR, config.tls.key_size)
    
    # Generate TLS parameters file if it doesn't exist
    params_file = "/etc/postfix/tls_params.pem"
    if not os.path.exists(params_file):
        logger.info("Generating TLS parameters file")
        subprocess.run([
            "openssl", "dhparam",
            "-out", params_file,
            str(config.tls.params_bits)
        ], check=True)
    
    # Configure Postfix TLS settings using Jinja2
    template_path = os.path.join(TEMPLATES_DIR, "tls_config.j2")
    output_path = "/etc/postfix/tls_config"
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {"config": config},
        "postfix"
    )
    
    # Run an initial certificate check to see if any renewals are needed
    # This will log the status of all certificates
    for domain in config.tls.domains:
        cert_path = os.path.join(CERTS_DIR, domain, "fullchain.pem")
        if os.path.exists(cert_path):
            needs_renewal = check_certificate_expiry(cert_path)
            if needs_renewal:
                logger.info(f"Certificate for {domain} should be renewed soon. Renewal will be handled by cron job.")
    
    logger.info("TLS configuration complete")

def print_tls_info(config: Configuration):
    """Print TLS configuration information."""
    if not config.tls.enabled:
        return
    
    logger.info("\n\n=== TLS CONFIGURATION ===")
    logger.info(f"TLS is enabled for domains: {', '.join(config.tls.domains)}")
    
    if config.tls.use_letsencrypt:
        logger.info("Using Let's Encrypt certificates")
        logger.info(f"Default challenge type: {config.tls.challenge_type}")
        if config.tls.challenge_type == "tls-alpn":
            logger.info("Using TLS-ALPN-01 challenge on ports 465/587 with HTTP fallback")
        
        for domain in config.tls.domains:
            cert_path = os.path.join(CERTS_DIR, domain, "fullchain.pem")
            if os.path.exists(cert_path):
                try:
                    output = subprocess.check_output([
                        "openssl", "x509", 
                        "-in", cert_path,
                        "-noout",
                        "-enddate",
                        "-issuer"
                    ]).decode('utf-8').strip()
                    logger.info(f"Certificate for {domain}:")
                    logger.info(output)
                except Exception as e:
                    logger.error(f"Error checking certificate for {domain}: {e}")
            else:
                logger.warning(f"Certificate for {domain} not found at {cert_path}")
    else:
        logger.info("Using self-signed certificates")
    
    logger.info("======================\n")

if __name__ == "__main__":
    # Test configuration
    from config import from_environment
    
    try:
        config = from_environment()
        configure_tls(config)
        print_tls_info(config)
    except Exception as e:
        logger.error(f"Error configuring TLS: {e}") 