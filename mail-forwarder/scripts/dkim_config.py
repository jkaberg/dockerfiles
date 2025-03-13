#!/usr/bin/env python3
"""
OpenDKIM configuration management for the mail forwarder.
"""

import os
import logging
import subprocess
import shutil
from pathlib import Path

from config import Configuration
from utils import render_template, ensure_template_exists

# Configure logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('dkim_config')

# Constants
OPENDKIM_CONF_DIR = "/etc/opendkim"
OPENDKIM_KEYS_DIR = os.path.join(OPENDKIM_CONF_DIR, "keys")
TEMPLATES_DIR = "/templates/opendkim"

def ensure_dkim_key(domain, selector, key_size):
    """Ensure DKIM key exists for the domain and selector."""
    domain_dir = os.path.join(OPENDKIM_KEYS_DIR, domain)
    key_file = os.path.join(domain_dir, f"{selector}.private")
    txt_file = os.path.join(domain_dir, f"{selector}.txt")
    
    # Check if key already exists
    if os.path.exists(key_file) and os.path.exists(txt_file):
        logger.info(f"DKIM key for {domain} with selector {selector} already exists")
        return key_file, txt_file
    
    # Ensure domain directory exists
    Path(domain_dir).mkdir(parents=True, exist_ok=True)
    
    # Generate new key
    logger.info(f"Generating new DKIM key for {domain} with selector {selector}")
    subprocess.run([
        "opendkim-genkey",
        "-b", str(key_size),
        "-d", domain,
        "-s", selector,
        "-D", domain_dir
    ], check=True)
    
    # Set permissions
    os.chmod(key_file, 0o640)
    os.chmod(txt_file, 0o644)
    
    return key_file, txt_file

def get_dkim_record(txt_file):
    """Extract the DKIM TXT record from the generated file."""
    with open(txt_file, 'r') as f:
        content = f.read()
    
    # Extract the record from the file
    # The file format is typically: selector._domainkey IN TXT ( "v=DKIM1; k=rsa; " "p=BASE64" )
    record = content.split('(')[1].split(')')[0].strip()
    record = record.replace('" "', '')
    record = record.replace('"', '')
    
    return record

def generate_dkim_dns_records(config: Configuration):
    """Generate DKIM DNS records for all domains."""
    dns_records = {}
    
    # The domains are now automatically derived from forwarding rules if not explicitly set
    for domain in config.dkim.domains:
        key_file, txt_file = ensure_dkim_key(domain, config.dkim.selector, config.dkim.key_size)
        
        # Get the DKIM record
        record = get_dkim_record(txt_file)
        
        # Store the DNS record
        dns_name = f"{config.dkim.selector}._domainkey.{domain}"
        dns_records[dns_name] = record
        
        logger.info(f"Generated DKIM DNS record for {domain}")
    
    return dns_records

def create_key_table(config: Configuration) -> None:
    """Create the OpenDKIM key table file using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "key_table.j2")
    output_path = os.path.join(OPENDKIM_CONF_DIR, "key_table")
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {
            "domains": sorted(config.dkim.domains),
            "selector": config.dkim.selector,
            "keys_dir": OPENDKIM_KEYS_DIR
        },
        "opendkim"
    )
    
    logger.info(f"Created OpenDKIM key table with {len(config.dkim.domains)} domains")

def create_signing_table(config: Configuration) -> None:
    """Create the OpenDKIM signing table file using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "signing_table.j2")
    output_path = os.path.join(OPENDKIM_CONF_DIR, "signing_table")
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {
            "domains": sorted(config.dkim.domains),
            "selector": config.dkim.selector
        },
        "opendkim"
    )
    
    logger.info(f"Created OpenDKIM signing table with {len(config.dkim.domains)} domains")

def create_trusted_hosts(config: Configuration) -> None:
    """Create the OpenDKIM trusted hosts file using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "trusted_hosts.j2")
    output_path = os.path.join(OPENDKIM_CONF_DIR, "trusted_hosts")
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {
            "domains": sorted(config.dkim.domains),
            "hostname": config.smtp.hostname
        },
        "opendkim"
    )
    
    logger.info(f"Created OpenDKIM trusted hosts file")

def create_dns_records_file(dns_records):
    """Create a file with DKIM DNS records for reference using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "dns_records.j2")
    output_path = os.path.join(OPENDKIM_CONF_DIR, "dns_records.txt")
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {"records": dns_records},
        None  # No service to reload for this file
    )
    
    logger.info(f"Generated DNS records file at {output_path}")

def create_spf_dmarc_instructions(config: Configuration) -> None:
    """Create a file with SPF and DMARC setup instructions using Jinja2 template."""
    template_path = os.path.join(TEMPLATES_DIR, "spf_dmarc_instructions.j2")
    output_path = os.path.join(OPENDKIM_CONF_DIR, "spf_dmarc_instructions.txt")
    
    # Render the template
    render_template(
        template_path,
        output_path,
        {"domains": sorted(config.dkim.domains)},
        None  # No service to reload for this file
    )
    
    logger.info(f"Generated SPF and DMARC instructions at {output_path}")

def configure_opendkim(config: Configuration) -> None:
    """Configure OpenDKIM using the provided configuration."""
    if not config.dkim.enabled:
        logger.info("DKIM is disabled, skipping OpenDKIM configuration")
        return
    
    logger.info("Configuring OpenDKIM")
    
    # Ensure directories exist
    Path(OPENDKIM_CONF_DIR).mkdir(exist_ok=True)
    Path(OPENDKIM_KEYS_DIR).mkdir(exist_ok=True)
    
    # Generate DKIM keys and DNS records
    dns_records = generate_dkim_dns_records(config)
    
    # Create key table
    create_key_table(config)
    
    # Create signing table
    create_signing_table(config)
    
    # Create trusted hosts
    create_trusted_hosts(config)
    
    # Create DNS records output file
    create_dns_records_file(dns_records)
    
    # Create SPF and DMARC instructions
    create_spf_dmarc_instructions(config)
    
    # Render opendkim.conf template
    render_template(
        os.path.join(TEMPLATES_DIR, "opendkim.conf.j2"),
        os.path.join(OPENDKIM_CONF_DIR, "opendkim.conf"),
        {
            "config": config,
            "key_table": os.path.join(OPENDKIM_CONF_DIR, "key_table"),
            "signing_table": os.path.join(OPENDKIM_CONF_DIR, "signing_table"),
            "trusted_hosts": os.path.join(OPENDKIM_CONF_DIR, "trusted_hosts"),
        },
        "opendkim"
    )
    
    logger.info("OpenDKIM configuration complete")

def print_dns_setup_instructions(config: Configuration) -> None:
    """Print DNS setup instructions for DKIM, SPF, and DMARC."""
    if not config.dkim.enabled:
        return
    
    dns_records_file = os.path.join(OPENDKIM_CONF_DIR, "dns_records.txt")
    spf_dmarc_file = os.path.join(OPENDKIM_CONF_DIR, "spf_dmarc_instructions.txt")
    
    logger.info("\n\n=== DKIM, SPF & DMARC DNS SETUP ===")
    logger.info("Add the following DNS records to your domain's DNS configuration:")
    
    if os.path.exists(dns_records_file):
        with open(dns_records_file, 'r') as f:
            logger.info(f.read())
    
    if os.path.exists(spf_dmarc_file):
        with open(spf_dmarc_file, 'r') as f:
            logger.info(f.read())
    
    logger.info("======================\n")

if __name__ == "__main__":
    # Test configuration
    from config import from_environment
    
    try:
        config = from_environment()
        configure_opendkim(config)
        print_dns_setup_instructions(config)
    except Exception as e:
        logger.error(f"Error configuring OpenDKIM: {e}") 