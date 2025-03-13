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
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('utils')

# Dictionary to store service reload callbacks
service_callbacks = {}

def register_service_callback(service_name: str, callback: Callable) -> None:
    """Register a callback function for a service to be called when configuration changes."""
    service_callbacks[service_name] = callback
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
        # Check if OpenDKIM is running
        if subprocess.run(["pgrep", "opendkim"], stdout=subprocess.PIPE).returncode == 0:
            subprocess.run(["kill", "-HUP", "`pgrep opendkim`"], shell=True, check=True)
            logger.info("Reloaded OpenDKIM configuration")
        else:
            # Start OpenDKIM if it's not running
            subprocess.run(["supervisorctl", "start", "opendkim"], check=True)
            logger.info("Started OpenDKIM service")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload OpenDKIM: {e}")

def reload_fail2ban() -> None:
    """Reload Fail2ban configuration."""
    try:
        subprocess.run(["fail2ban-client", "reload"], check=True)
        logger.info("Reloaded Fail2ban configuration")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to reload Fail2ban: {e}")
        # Try to start it via supervisor
        try:
            subprocess.run(["supervisorctl", "start", "fail2ban"], check=True)
            logger.info("Started Fail2ban service")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to start Fail2ban: {e}")

# Register callbacks for services
register_service_callback("postfix", reload_postfix)
register_service_callback("opendkim", reload_opendkim)
register_service_callback("fail2ban", reload_fail2ban) 