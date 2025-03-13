#!/usr/bin/env python3
"""
Shared utilities for the mail forwarder.
Contains common functions used across multiple modules.
"""

import os
import logging
import subprocess
import jinja2
from typing import Dict, Any, Callable, Optional

# Configure logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('utils')

# Dictionary to store service reload callbacks and service check functions
service_callbacks = {}
service_check_funcs = {}

def register_service_callback(service_name: str, callback: Callable, check_func: Optional[Callable] = None) -> None:
    """
    Register a callback function for a service to be called when configuration changes.
    
    Args:
        service_name: Name of the service to register
        callback: Function to call when the service needs to be reloaded
        check_func: Optional function that returns True if the service should be active
    """
    service_callbacks[service_name] = callback
    if check_func:
        service_check_funcs[service_name] = check_func
    logger.debug(f"Registered callback for service: {service_name}")

def ensure_template_exists(template_path: str, template_content: str) -> None:
    """
    Ensure that a template file exists.
    If not, create it with the provided content.
    
    Args:
        template_path: Path where the template should be
        template_content: The content to write to the template if it doesn't exist
    """
    if os.path.exists(template_path):
        return
    
    # Create the directory if it doesn't exist
    os.makedirs(os.path.dirname(template_path), exist_ok=True)
    
    # Create the template file
    with open(template_path, 'w') as f:
        f.write(template_content)
    
    logger.debug(f"Created template at {template_path}")

def render_template(template_path: str, output_path: str, context: Dict[str, Any], 
                    service_name: Optional[str] = None) -> None:
    """
    Render a Jinja2 template to a file and optionally reload the associated service.
    
    Args:
        template_path: Path to the template file
        output_path: Path where the rendered file should be saved
        context: Dictionary with variables to use in the template
        service_name: Name of the service to reload after rendering (if any)
    """
    try:
        # Ensure the output directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Load and render the template
        template_dir = os.path.dirname(template_path)
        template_file = os.path.basename(template_path)
        
        template_loader = jinja2.FileSystemLoader(searchpath=template_dir)
        template_env = jinja2.Environment(loader=template_loader)
        template = template_env.get_template(template_file)
        output_text = template.render(**context)
        
        # Check if the file exists and content is different
        content_changed = True
        if os.path.exists(output_path):
            with open(output_path, 'r') as f:
                existing_content = f.read()
                if existing_content == output_text:
                    content_changed = False
        
        if content_changed:
            # Write the rendered content to the output file
            with open(output_path, 'w') as f:
                f.write(output_text)
            
            logger.info(f"Generated {output_path}")
            
            # Call service callback if provided and content changed
            if service_name and service_name in service_callbacks:
                # Check if the service should be active if there's a check function
                if service_name in service_check_funcs:
                    check_func = service_check_funcs[service_name]
                    if not check_func():
                        logger.info(f"Service {service_name} is not enabled in configuration, skipping reload")
                        return
                
                logger.info(f"Calling callback for service: {service_name}")
                service_callbacks[service_name]()
        else:
            logger.debug(f"No changes to {output_path}, skipping")
    except Exception as e:
        logger.error(f"Error rendering template {template_path} to {output_path}: {e}")
        raise

def reload_postfix() -> None:
    """Reload Postfix configuration."""
    try:
        subprocess.run(["postfix", "reload"], check=True)
        logger.info("Reloaded Postfix configuration")
    except subprocess.CalledProcessError:
        logger.info("Starting Postfix service")
        subprocess.run(["postfix", "start"], check=True)

def reload_opendkim() -> None:
    """Reload OpenDKIM configuration."""
    try:
        # Check if supervisor is properly configured
        if not os.path.exists("/var/run/supervisor.sock"):
            logger.warning("Supervisor socket not found, skipping OpenDKIM reload")
            return
        
        # Check if OpenDKIM is running
        if subprocess.run(["pgrep", "opendkim"], stdout=subprocess.PIPE).returncode == 0:
            subprocess.run(["kill", "-HUP", "`pgrep opendkim`"], shell=True, check=True)
            logger.info("Reloaded OpenDKIM configuration")
        else:
            # Only try to start OpenDKIM if supervisor is ready
            try:
                subprocess.run(["supervisorctl", "start", "opendkim"], check=True)
                logger.info("Started OpenDKIM service")
            except subprocess.CalledProcessError as e:
                if "not include supervisorctl section" in str(e):
                    logger.error("Supervisor configuration is incomplete. Will try again later.")
                else:
                    logger.error(f"Failed to start OpenDKIM: {e}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload OpenDKIM: {e}")

def reload_fail2ban() -> None:
    """Reload Fail2ban configuration."""
    try:
        # Check if supervisor is properly configured
        if not os.path.exists("/var/run/supervisor.sock"):
            logger.warning("Supervisor socket not found, skipping Fail2ban reload")
            return
            
        subprocess.run(["fail2ban-client", "reload"], check=True)
        logger.info("Reloaded Fail2ban configuration")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload Fail2ban: {e}")
        # Try to start it via supervisor
        try:
            subprocess.run(["supervisorctl", "start", "fail2ban"], check=True)
            logger.info("Started Fail2ban service")
        except subprocess.CalledProcessError as e:
            if "not include supervisorctl section" in str(e):
                logger.error("Supervisor configuration is incomplete. Will try again later.")
            else:
                logger.error(f"Failed to start Fail2ban: {e}")

def reload_postsrsd() -> None:
    """Reload PostSRSd configuration."""
    try:
        # Check if supervisor is properly configured
        if not os.path.exists("/var/run/supervisor.sock"):
            logger.warning("Supervisor socket not found, skipping PostSRSd reload")
            return
            
        # Check if PostSRSd is running
        if subprocess.run(["pgrep", "postsrsd"], stdout=subprocess.PIPE).returncode == 0:
            subprocess.run(["supervisorctl", "restart", "postsrsd"], check=True)
            logger.info("Restarted PostSRSd service")
        else:
            # Start PostSRSd if it's not running
            try:
                subprocess.run(["supervisorctl", "start", "postsrsd"], check=True)
                logger.info("Started PostSRSd service")
            except subprocess.CalledProcessError as e:
                if "not include supervisorctl section" in str(e):
                    logger.error("Supervisor configuration is incomplete. Will try again later.")
                else:
                    logger.error(f"Failed to start PostSRSd: {e}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload PostSRSd: {e}")

def reload_saslauthd() -> None:
    """Reload SASL authentication daemon configuration."""
    try:
        # Check if supervisor is properly configured
        if not os.path.exists("/var/run/supervisor.sock"):
            logger.warning("Supervisor socket not found, skipping SASL authentication daemon reload")
            return
            
        # Check if saslauthd is running
        if subprocess.run(["pgrep", "saslauthd"], stdout=subprocess.PIPE).returncode == 0:
            subprocess.run(["supervisorctl", "restart", "saslauthd"], check=True)
            logger.info("Restarted SASL authentication daemon")
        else:
            # Start saslauthd if it's not running
            try:
                subprocess.run(["supervisorctl", "start", "saslauthd"], check=True)
                logger.info("Started SASL authentication daemon")
            except subprocess.CalledProcessError as e:
                if "not include supervisorctl section" in str(e):
                    logger.error("Supervisor configuration is incomplete. Will try again later.")
                else:
                    logger.error(f"Failed to start SASL authentication daemon: {e}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload SASL authentication daemon: {e}")

# Note: Service callback registrations are now in their respective configuration modules
# for better service state tracking. See:
# - dkim_config.py for opendkim
# - postfix_config.py for postsrsd and saslauthd
# - security_config.py for fail2ban
# Postfix is always required so it will be registered when postfix_config is imported 