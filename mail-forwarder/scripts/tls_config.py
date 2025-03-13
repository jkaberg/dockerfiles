#!/usr/bin/env python3
"""
TLS certificate management for the mail forwarder.
"""

import os
import logging
import subprocess
import shutil
from pathlib import Path
import time
import datetime
import threading

from config import Configuration
from utils import render_template, ensure_template_exists

# Configure logging
logging.basicConfig(
    level=logging.INFO,
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
RENEWAL_THRESHOLD_DAYS = 30  # Renew certificates if they expire within 30 days

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
    
    # Prepare base command
    base_cmd = [
        "certbot", "certonly",
        "--non-interactive",
        "--agree-tos",
        "--email", email,
        "--cert-name", domain,
        "-d", domain
    ]
    
    if staging:
        base_cmd.append("--test-cert")
    
    # First try with TLS-ALPN-01 challenge on port 465 (SMTPS)
    logger.info(f"Attempting to set up Let's Encrypt certificate for {domain} using TLS-ALPN-01 challenge on port 465")
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
    
    # Try with TLS-ALPN-01 challenge on port 587 (Submission) as alternative
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

def renew_certificates():
    """Renew all certificates using certbot."""
    try:
        logger.info("Attempting to renew certificates using TLS-ALPN-01 challenge on port 465")
        # First try with TLS-ALPN-01 on port 465
        try:
            subprocess.run([
                "certbot", "renew", 
                "--non-interactive", 
                "--preferred-challenges", "tls-alpn-01",
                "--tls-alpn-port", "465"
            ], check=True)
            logger.info("Certificate renewal completed successfully using TLS-ALPN-01 on port 465")
            return
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to renew certificates using TLS-ALPN-01 on port 465: {e}")
        
        # Try with TLS-ALPN-01 on port 587
        logger.info("Attempting to renew certificates using TLS-ALPN-01 challenge on port 587")
        try:
            subprocess.run([
                "certbot", "renew", 
                "--non-interactive", 
                "--preferred-challenges", "tls-alpn-01",
                "--tls-alpn-port", "587"
            ], check=True)
            logger.info("Certificate renewal completed successfully using TLS-ALPN-01 on port 587")
            return
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to renew certificates using TLS-ALPN-01 on port 587: {e}")
        
        # Fall back to HTTP-01 challenge
        logger.info("Falling back to HTTP-01 challenge for certificate renewal")
        subprocess.run([
            "certbot", "renew", 
            "--non-interactive", 
            "--preferred-challenges", "http-01"
        ], check=True)
        logger.info("Certificate renewal completed successfully using HTTP-01")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to renew certificates using all methods: {e}")

def setup_auto_renewal():
    """Set up automatic certificate renewal."""
    def renewal_thread():
        while True:
            # Check every 12 hours
            time.sleep(12 * 60 * 60)
            
            # Renew if needed
            try:
                # Check for any certificates that need renewal
                renewal_needed = False
                
                for domain in os.listdir(CERTS_DIR):
                    cert_path = os.path.join(CERTS_DIR, domain, "fullchain.pem")
                    if os.path.exists(cert_path) and check_certificate_expiry(cert_path):
                        renewal_needed = True
                        break
                
                # Renew certificates if needed
                if renewal_needed:
                    renew_certificates()
            except Exception as e:
                logger.error(f"Error in renewal thread: {e}")
    
    # Start the renewal thread
    thread = threading.Thread(target=renewal_thread, daemon=True)
    thread.start()
    logger.info("Automatic certificate renewal setup complete")

def configure_tls(config: Configuration):
    """Configure TLS certificates based on the provided configuration."""
    if not config.tls.enabled:
        logger.info("TLS is disabled, skipping certificate configuration")
        return
    
    logger.info("Configuring TLS certificates")
    
    # Ensure directories exist
    Path(POSTFIX_CERT_DIR).mkdir(parents=True, exist_ok=True)
    
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
    
    # Set up automatic renewal
    if config.tls.use_letsencrypt:
        setup_auto_renewal()
    
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