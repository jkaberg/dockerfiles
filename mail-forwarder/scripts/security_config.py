#!/usr/bin/env python3
"""
Security configuration management for the mail forwarder.
Configures Fail2ban for protection against brute-force attacks.
"""

import os
import logging
import subprocess
from pathlib import Path

from config import Configuration
from utils import render_template, ensure_template_exists

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('security_config')

# Constants
FAIL2BAN_CONF_DIR = "/etc/fail2ban"
TEMPLATES_DIR = "/templates/fail2ban"

def configure_fail2ban(config: Configuration) -> None:
    """Configure Fail2ban using the provided configuration."""
    if not config.security.fail2ban_enabled:
        logger.info("Fail2ban is disabled, skipping configuration")
        return
    
    logger.info("Configuring Fail2ban")
    
    # Ensure directories exist
    Path(FAIL2BAN_CONF_DIR).mkdir(exist_ok=True)
    Path(os.path.join(FAIL2BAN_CONF_DIR, "jail.d")).mkdir(exist_ok=True)
    Path(os.path.join(FAIL2BAN_CONF_DIR, "filter.d")).mkdir(exist_ok=True)
    
    # Render jail.local template
    template_path = os.path.join(TEMPLATES_DIR, "jail.local.j2")
    
    render_template(
        template_path,
        os.path.join(FAIL2BAN_CONF_DIR, "jail.local"),
        {
            "config": config,
            "max_attempts": config.security.max_attempts,
            "ban_time": config.security.ban_time,
            "find_time": config.security.find_time,
        },
        "fail2ban"
    )
    
    # Render postfix-sasl filter
    template_path = os.path.join(TEMPLATES_DIR, "postfix-sasl.conf.j2")
    
    render_template(
        template_path,
        os.path.join(FAIL2BAN_CONF_DIR, "filter.d", "postfix-sasl.conf"),
        {"config": config},
        "fail2ban"
    )
    
    # Enable the postfix-sasl jail
    template_path = os.path.join(TEMPLATES_DIR, "postfix.conf.j2")
    
    render_template(
        template_path,
        os.path.join(FAIL2BAN_CONF_DIR, "jail.d", "postfix.conf"),
        {
            "config": config,
            "max_attempts": config.security.max_attempts,
            "ban_time": config.security.ban_time,
            "find_time": config.security.find_time,
        },
        "fail2ban"
    )
    
    # Restart Fail2ban
    try:
        subprocess.run(["fail2ban-client", "reload"], check=True)
        logger.info("Reloaded Fail2ban configuration")
    except subprocess.CalledProcessError:
        logger.info("Starting Fail2ban service")
        # Will be started by supervisor

def get_ban_status():
    """Get the current ban status from Fail2ban."""
    try:
        output = subprocess.check_output(
            ["fail2ban-client", "status"],
            universal_newlines=True
        )
        logger.info(f"Fail2ban status: {output.strip()}")
        
        # Get details for postfix jails
        output = subprocess.check_output(
            ["fail2ban-client", "status", "postfix-sasl"],
            universal_newlines=True
        )
        logger.info(f"Postfix SASL jail status: {output.strip()}")
        
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to get Fail2ban status: {e}")
        return False

if __name__ == "__main__":
    # Test configuration
    from config import from_environment
    
    try:
        config = from_environment()
        configure_fail2ban(config)
        get_ban_status()
    except Exception as e:
        logger.error(f"Error configuring Fail2ban: {e}") 