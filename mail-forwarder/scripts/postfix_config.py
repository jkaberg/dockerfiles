#!/usr/bin/env python3
"""
Postfix configuration management for the mail forwarder.
"""

import os
import logging
import subprocess
from pathlib import Path

from config import Configuration, ForwardingRule
from utils import render_template, ensure_template_exists
from utils import register_service_callback, reload_postsrsd, reload_saslauthd, reload_postfix

# Configure logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('postfix_config')

# Constants
POSTFIX_CONF_DIR = "/etc/postfix"
VIRTUAL_ALIAS_FILE = os.path.join(POSTFIX_CONF_DIR, "virtual")
TRANSPORT_MAP_FILE = os.path.join(POSTFIX_CONF_DIR, "transport")
SASL_PASSWD_FILE = os.path.join(POSTFIX_CONF_DIR, "sasl_passwd")
SMTP_AUTH_FILE = os.path.join(POSTFIX_CONF_DIR, "sasl_users")
TEMPLATES_DIR = "/templates/postfix"
POSTSRSD_CONFIG_FILE = "/etc/default/postsrsd"

# Global variable to store the current configuration
_config = None

def is_srs_enabled():
    """Check if SRS is enabled in the current configuration."""
    global _config
    return _config is not None and _config.srs.enabled

def is_sasl_auth_enabled():
    """Check if SASL auth is enabled in the current configuration."""
    global _config
    return _config is not None and _config.smtp.smtp_auth_enabled

# Register the callbacks with the check functions
register_service_callback("postfix", reload_postfix)  # Postfix is always required
register_service_callback("postsrsd", reload_postsrsd, is_srs_enabled)
register_service_callback("saslauthd", reload_saslauthd, is_sasl_auth_enabled)

def create_virtual_alias_map(config: Configuration) -> None:
    """Create the virtual alias map from the forwarding rules using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "virtual.j2")
    
    # Render the template
    render_template(
        template_path,
        VIRTUAL_ALIAS_FILE,
        {"rules": sorted(config.forwarding_rules, key=lambda r: r.source)},
        "postfix"
    )
    
    # Generate the database
    subprocess.run(["postmap", VIRTUAL_ALIAS_FILE], check=True)
    logger.info(f"Created virtual alias map with {len(config.forwarding_rules)} rules")

def create_transport_map(config: Configuration) -> None:
    """Create the transport map for SMTP relay using Jinja2 template."""
    if not config.smtp.relay_host:
        return
    
    template_path = os.path.join(TEMPLATES_DIR, "transport.j2")
    
    # Get unique domains from forwarding rules
    domains = {rule.domain for rule in config.forwarding_rules if rule.domain != config.smtp.hostname}
    
    # Render the template
    render_template(
        template_path,
        TRANSPORT_MAP_FILE,
        {
            "domains": sorted(domains),
            "relay_host": config.smtp.relay_host,
            "relay_port": config.smtp.relay_port
        },
        "postfix"
    )
    
    # Generate the database
    subprocess.run(["postmap", TRANSPORT_MAP_FILE], check=True)
    logger.info(f"Created transport map for relay through {config.smtp.relay_host}")

def create_sasl_passwd(config: Configuration) -> None:
    """Create the SASL password file for SMTP authentication using Jinja2 template."""
    if not (config.smtp.relay_host and config.smtp.relay_username and config.smtp.relay_password):
        return
    
    template_path = os.path.join(TEMPLATES_DIR, "sasl_passwd.j2")
    
    # Render the template
    render_template(
        template_path,
        SASL_PASSWD_FILE,
        {
            "relay_host": config.smtp.relay_host,
            "relay_port": config.smtp.relay_port,
            "username": config.smtp.relay_username,
            "password": config.smtp.relay_password
        },
        "postfix"
    )
    
    # Generate the database and secure it
    subprocess.run(["postmap", SASL_PASSWD_FILE], check=True)
    os.chmod(SASL_PASSWD_FILE, 0o600)
    os.chmod(f"{SASL_PASSWD_FILE}.db", 0o600)
    logger.info(f"Created SASL password file for relay through {config.smtp.relay_host}")

def create_sasl_auth_users(config: Configuration) -> None:
    """Create the SASL auth users file for SMTP authentication."""
    if not config.smtp.smtp_auth_enabled or not config.smtp.smtp_users:
        return
    
    logger.info(f"Creating SASL auth users file with {len(config.smtp.smtp_users)} users")
    
    # Create SASL password database for Postfix
    with open(SMTP_AUTH_FILE, "w") as f:
        for username, password in config.smtp.smtp_users.items():
            f.write(f"{username}:{password}\n")
    
    # Generate the database and secure it
    subprocess.run(["postmap", SMTP_AUTH_FILE], check=True)
    os.chmod(SMTP_AUTH_FILE, 0o600)
    os.chmod(f"{SMTP_AUTH_FILE}.db", 0o600)
    
    # Create sasl authentication configuration
    os.makedirs("/etc/sasl2", exist_ok=True)
    with open("/etc/sasl2/smtpd.conf", "w") as f:
        f.write("pwcheck_method: auxprop\n")
        f.write("auxprop_plugin: sasldb\n")
        f.write("mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5\n")
        f.write(f"sasldb_path: {SMTP_AUTH_FILE}.db\n")
    
    logger.info("Created SASL authentication configuration")

def configure_srs(config: Configuration) -> None:
    """Configure SRS (Sender Rewriting Scheme) if enabled."""
    if not config.srs.enabled:
        logger.info("SRS is disabled, skipping configuration")
        return
    
    logger.info("Configuring SRS (Sender Rewriting Scheme)")
    
    # If SRS domain is not set, use SMTP hostname
    srs_domain = config.srs.domain
    if not srs_domain:
        srs_domain = config.smtp.hostname
        logger.info(f"SRS domain not set, using SMTP hostname: {srs_domain}")
    
    # If SRS secret is not set, warn about it - it should be set for security
    if not config.srs.secret:
        logger.warning("SRS secret not set - a random one will be generated on each restart")
    
    # Create postsrsd config file
    with open(POSTSRSD_CONFIG_FILE, "w") as f:
        f.write(f'# Configuration file for postsrsd\n')
        f.write(f'# Generated by mail-forwarder\n\n')
        f.write(f'RUN=yes\n')
        f.write(f'SRS_DOMAIN={srs_domain}\n')
        
        # Only write the secret if it's available
        if config.srs.secret:
            f.write(f'SRS_SECRET={config.srs.secret}\n')
        
        # Add excluded domains if any
        if config.srs.exclude_domains:
            domains_str = ' '.join(sorted(config.srs.exclude_domains))
            f.write(f'SRS_EXCLUDE_DOMAINS="{domains_str}"\n')
        
        # Set some sensible defaults
        f.write(f'SRS_SEPARATOR=+\n')
        f.write(f'SRS_FORWARD_PORT=10001\n')
        f.write(f'SRS_REVERSE_PORT=10002\n')
    
    # Informational message - we're now using supervisor to start the service
    logger.info(f"SRS configured with domain {srs_domain}")
    
    # Update the config with the domain we're using (if it wasn't set)
    if not config.srs.domain:
        config.srs.domain = srs_domain

def configure_postfix(config: Configuration) -> None:
    """Configure Postfix using the provided configuration."""
    global _config
    _config = config
    
    logger.info("Configuring Postfix")
    
    # Ensure directories exist
    Path(POSTFIX_CONF_DIR).mkdir(exist_ok=True)
    
    # Configure SRS if enabled
    configure_srs(config)
    
    # Render main.cf template
    render_template(
        os.path.join(TEMPLATES_DIR, "main.cf.j2"),
        os.path.join(POSTFIX_CONF_DIR, "main.cf"),
        {
            "config": config,
            "hostname": config.smtp.hostname,
            "helo_name": config.smtp.helo_name,  # Now this is always set (defaults to hostname)
            "relay_host": config.smtp.relay_host,
            "relay_port": config.smtp.relay_port,
            "relay_username": config.smtp.relay_username,
            "relay_password": config.smtp.relay_password,
            "use_tls": config.smtp.use_tls,
            "virtual_alias_map": VIRTUAL_ALIAS_FILE,
            "srs_enabled": config.srs.enabled,
        },
        "postfix"
    )
    
    # Render master.cf template
    render_template(
        os.path.join(TEMPLATES_DIR, "master.cf.j2"),
        os.path.join(POSTFIX_CONF_DIR, "master.cf"),
        {
            "config": config,
            "enable_smtp": config.smtp.enable_smtp,
            "enable_submission": config.smtp.enable_submission,
            "enable_smtps": config.smtp.enable_smtps,
            "smtp_auth_enabled": config.smtp.smtp_auth_enabled,
        },
        "postfix"
    )
    
    # Create virtual alias map
    create_virtual_alias_map(config)
    
    # Configure transport map if using SMTP relay
    if config.smtp.relay_host:
        create_transport_map(config)
        
        # Configure SASL authentication if credentials are provided
        if config.smtp.relay_username and config.smtp.relay_password:
            create_sasl_passwd(config)
    
    # Configure SMTP auth users if enabled
    if config.smtp.smtp_auth_enabled:
        create_sasl_auth_users(config)

if __name__ == "__main__":
    # Test configuration
    from config import from_environment
    
    try:
        config = from_environment()
        configure_postfix(config)
    except Exception as e:
        logger.error(f"Error configuring Postfix: {e}") 