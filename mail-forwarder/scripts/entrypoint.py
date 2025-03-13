#!/usr/bin/env python3
"""
Entrypoint script for the mail forwarder container.
Handles initialization, configuration, and service management.
"""

import os
import sys
import logging
import subprocess
import time
import argparse
import socket
import dns.resolver
from tabulate import tabulate
from pathlib import Path
import io

# Import configuration modules
from config import Configuration, from_environment
from postfix_config import configure_postfix
from dkim_config import configure_opendkim, print_dns_setup_instructions as print_dkim_dns
from tls_config import configure_tls, setup_cron_job as setup_auto_renewal, print_tls_info
from security_config import configure_fail2ban
from utils import render_template, ensure_template_exists

# Configure logging to only show warnings and errors
logging.basicConfig(
    level=logging.WARNING,  # Changed from INFO to WARNING
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()  # This sends logs to stderr
    ]
)
logger = logging.getLogger('entrypoint')

def setup_supervisor(config: Configuration):
    """Set up the supervisor configuration."""
    supervisor_conf = "/etc/supervisor/conf.d/mail-forwarder.conf"
    template_path = "/templates/supervisor/mail-forwarder.conf.j2"
    
    # Render the template
    render_template(
        template_path,
        supervisor_conf,
        {"config": config},
        None  # No service to reload for this file
    )
    # Only log at debug level instead of info
    logger.debug("Generated supervisor configuration from template")

def check_dns_records(config: Configuration):
    """Check current DNS records for the configured domains."""
    dns_results = []
    resolver = dns.resolver.Resolver()
    resolver.timeout = 5
    resolver.lifetime = 5
    
    for domain in sorted(config.dkim.domains):
        # Check MX record
        mx_wanted = f"{config.smtp.hostname}."
        mx_current = "Not found"
        mx_valid = False
        
        try:
            answers = resolver.resolve(domain, 'MX')
            for rdata in answers:
                mx_current = str(rdata.exchange).rstrip('.')
                if mx_current == config.smtp.hostname:
                    mx_valid = True
                    break
        except Exception as e:
            mx_current = f"Error: {str(e)}"
        
        dns_results.append(["MX", domain, mx_valid, mx_current, mx_wanted])
        
        # Check SPF record
        spf_wanted = "v=spf1 mx -all"
        spf_current = "Not found"
        spf_valid = False
        
        try:
            answers = resolver.resolve(domain, 'TXT')
            for rdata in answers:
                txt_data = "".join(str(txt) for txt in rdata.strings)
                if txt_data.startswith("v=spf1"):
                    spf_current = txt_data
                    if txt_data == spf_wanted:
                        spf_valid = True
                    break
        except Exception as e:
            spf_current = f"Error: {str(e)}"
        
        dns_results.append(["SPF (TXT)", domain, spf_valid, spf_current, spf_wanted])
        
        # Check DKIM record
        dkim_selector = config.dkim.selector
        dkim_name = f"{dkim_selector}._domainkey.{domain}"
        dkim_current = "Not found"
        dkim_valid = False
        
        # Get expected DKIM record from file
        dkim_wanted = "DKIM record not generated yet"
        dkim_records_file = f"/etc/opendkim/dns_records.txt"
        if os.path.exists(dkim_records_file):
            with open(dkim_records_file, 'r') as f:
                for line in f:
                    if dkim_name in line and "IN TXT" in line:
                        dkim_wanted = line.split("IN TXT")[1].strip()
                        break
        
        try:
            answers = resolver.resolve(dkim_name, 'TXT')
            for rdata in answers:
                txt_data = "".join(str(txt) for txt in rdata.strings)
                dkim_current = txt_data
                if "v=DKIM1" in txt_data:
                    # Simplified validation - just check if it contains the basics
                    dkim_valid = True
                    break
        except Exception as e:
            dkim_current = f"Error: {str(e)}"
        
        dns_results.append(["DKIM (TXT)", dkim_name, dkim_valid, dkim_current, dkim_wanted])
        
        # Check DMARC record
        dmarc_name = f"_dmarc.{domain}"
        dmarc_wanted = "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; fo=1;"
        dmarc_current = "Not found"
        dmarc_valid = False
        
        try:
            answers = resolver.resolve(dmarc_name, 'TXT')
            for rdata in answers:
                txt_data = "".join(str(txt) for txt in rdata.strings)
                if txt_data.startswith("v=DMARC1"):
                    dmarc_current = txt_data
                    if "p=reject" in txt_data:
                        dmarc_valid = True
                    break
        except Exception as e:
            dmarc_current = f"Error: {str(e)}"
        
        dns_results.append(["DMARC (TXT)", dmarc_name, dmarc_valid, dmarc_current, dmarc_wanted])
    
    return dns_results

def is_supervisor_ready():
    """Check if supervisor is ready by checking for the existence of the socket file."""
    supervisor_sock = "/var/run/supervisor.sock"
    return os.path.exists(supervisor_sock)

def wait_for_supervisor(timeout=30):
    """Wait for supervisor to be ready by checking the socket file."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        if is_supervisor_ready():
            logger.info("Supervisor is ready")
            return True
        logger.info("Waiting for supervisor to be ready...")
        time.sleep(1)
    logger.error(f"Supervisor did not become ready within {timeout} seconds")
    return False

def initialize(config: Configuration):
    """Initialize the mail forwarder container."""
    try:
        # Create required directories
        Path("/templates").mkdir(exist_ok=True)
        Path("/templates/postfix").mkdir(exist_ok=True)
        Path("/templates/opendkim").mkdir(exist_ok=True)
        Path("/templates/tls").mkdir(exist_ok=True)
        Path("/templates/fail2ban").mkdir(exist_ok=True)
        Path("/templates/supervisor").mkdir(exist_ok=True)
        
        # First, generate supervisor configuration
        setup_supervisor(config)
        
        # Configure all services before starting supervisord
        
        # 1. OpenDKIM first (needed by Postfix)
        configure_opendkim(config)
        
        # 2. TLS certificates
        configure_tls(config)
        
        # 3. Postfix (depends on OpenDKIM and TLS)
        configure_postfix(config)
        
        # 4. Security (fail2ban)
        if config.security.fail2ban_enabled:
            configure_fail2ban(config)
        
        # Print DNS setup instructions
        print_dkim_dns(config)
        print_tls_info(config)
        
        # Finally, start supervisord which will start all services
        logger.info("Starting supervisord to manage all services...")
        subprocess.run(["supervisord", "-c", "/etc/supervisor/supervisord.conf"], check=True)
        
        # Wait for supervisor to be ready
        if not wait_for_supervisor():
            raise RuntimeError("Supervisor failed to initialize within the timeout period")
            
        logger.info("Supervisord started successfully, all services should now be running")
        
        return True
    except Exception as e:
        logger.error(f"Initialization failed: {e}")
        return False

def show_config_table(config: Configuration):
    """Display the configuration in a formatted table."""
    # Capture stdout to a string buffer
    old_stdout = sys.stdout
    sys.stdout = buffer = io.StringIO()
    
    # Basic configuration
    print("\n🌐 Basic Configuration:")
    basic_table = [
        ["SMTP Hostname", config.smtp.hostname],
        ["HELO Name", config.smtp.helo_name],
        ["Debug Mode", "Enabled" if config.debug else "Disabled"],
    ]
    print(tabulate(basic_table, tablefmt="plain"))
    
    # Ports configuration
    print("\n🔌 Ports:")
    ports_table = [
        ["Port 25 (SMTP)", "Enabled" if config.smtp.enable_smtp else "Disabled"],
        ["Port 587 (Submission)", "Enabled" if config.smtp.enable_submission else "Disabled"],
        ["Port 465 (SMTPS)", "Enabled" if config.smtp.enable_smtps else "Disabled"],
    ]
    print(tabulate(ports_table, tablefmt="plain"))
    
    # Forwarding rules
    print("\n📧 Forwarding Rules:")
    rules_table = []
    for rule in config.forwarding_rules:
        rules_table.append([rule.source, "→", rule.destination])
    print(tabulate(rules_table, tablefmt="plain"))
    
    # DKIM configuration
    print("\n🔑 DKIM Configuration:")
    dkim_table = [
        ["Enabled", "Yes" if config.dkim.enabled else "No"],
    ]
    if config.dkim.enabled:
        dkim_table.extend([
            ["Selector", config.dkim.selector],
            ["Key Size", f"{config.dkim.key_size} bits"],
            ["Domains", ", ".join(sorted(config.dkim.domains)) if config.dkim.domains else "None"],
        ])
    print(tabulate(dkim_table, tablefmt="plain"))
    
    # TLS configuration
    print("\n🔒 TLS Configuration:")
    tls_table = [
        ["Enabled", "Yes" if config.tls.enabled else "No"],
    ]
    if config.tls.enabled:
        tls_table.extend([
            ["Email", config.tls.email],
            ["Challenge Type", config.tls.challenge_type],
            ["Staging", "Yes" if config.tls.staging else "No"],
            ["Domains", ", ".join(sorted(config.tls.domains)) if config.tls.domains else "None"],
        ])
    print(tabulate(tls_table, tablefmt="plain"))
    
    # SRS configuration
    print("\n🔄 SRS (Sender Rewriting Scheme) Configuration:")
    srs_table = [
        ["Enabled", "Yes" if config.srs.enabled else "No"],
    ]
    if config.srs.enabled:
        srs_table.extend([
            ["Domain", config.srs.domain],
            ["Secret", "Set" if config.srs.secret else "Not Set"],
            ["Excluded Domains", ", ".join(sorted(config.srs.exclude_domains)) if config.srs.exclude_domains else "None"],
        ])
    print(tabulate(srs_table, tablefmt="plain"))
    
    # SMTP relay configuration
    print("\n🔀 SMTP Relay Configuration:")
    relay_table = [
        ["Relay Host", config.smtp.relay_host if config.smtp.relay_host else "None"],
    ]
    if config.smtp.relay_host:
        relay_table.extend([
            ["Relay Port", config.smtp.relay_port],
            ["Use TLS", "Yes" if config.smtp.use_tls else "No"],
            ["Authentication", "Yes" if config.smtp.relay_username and config.smtp.relay_password else "No"],
        ])
    print(tabulate(relay_table, tablefmt="plain"))
    
    # Security configuration
    print("\n🛡️ Security Configuration:")
    security_table = [
        ["Fail2Ban", "Enabled" if config.security.fail2ban_enabled else "Disabled"],
    ]
    if config.security.fail2ban_enabled:
        security_table.extend([
            ["Max Attempts", config.security.max_attempts],
            ["Ban Time", f"{config.security.ban_time} seconds"],
            ["Find Time", f"{config.security.find_time} seconds"],
        ])
    print(tabulate(security_table, tablefmt="plain"))
    
    # Get the output and restore stdout
    output = buffer.getvalue()
    sys.stdout = old_stdout
    
    return output

def show_dns_table(dns_results):
    """Display DNS records in a tabular format with clear comparison between current and expected values."""
    if not dns_results:
        return
    
    print("\n==== DNS RECORDS CONFIGURATION ====\n")
    
    # Group DNS results by type for better organization
    records_by_type = {}
    for record in dns_results:
        record_type = record[0]  # TYPE column
        if record_type not in records_by_type:
            records_by_type[record_type] = []
        records_by_type[record_type].append(record)
    
    # Print each record type in its own section
    for record_type, records in records_by_type.items():
        print(f"===== {record_type} RECORDS =====")
        print(tabulate(
            records,
            headers=["TYPE", "NAME", "VALID", "CURRENT VALUE", "EXPECTED VALUE"],
            tablefmt="pretty"
        ))
        print("\n")
    
    # Count valid records
    valid_count = sum(1 for r in dns_results if r[2])
    total_count = len(dns_results)
    
    # Summary section
    print("===== DNS CONFIGURATION SUMMARY =====")
    summary_table = [
        ["Total Records", total_count],
        ["Correctly Configured", valid_count],
        ["Needs Configuration", total_count - valid_count],
        ["Status", "✅ All Good" if valid_count == total_count else "❌ Action Required"]
    ]
    print(tabulate(summary_table, tablefmt="pretty"))
    
    if valid_count < total_count:
        print("\n⚠️ IMPORTANT: Please update your DNS records to match the EXPECTED VALUES.")
        print("This is critical for proper email delivery and security.")
        print("Changes may take 24-48 hours to propagate through the DNS system.")

def run():
    """
    Initialize the mail forwarder and output configuration information.
    Configuration and services are managed by supervisord after initialization.
    """
    try:
        # Load configuration
        config = from_environment()
        
        # Initialize the container
        if initialize(config):
            print("Initialization complete")
            
            # Show configuration
            show_config_table(config)
            
            # Check DNS records
            time.sleep(2)  # Brief delay to allow services to start
            dns_results = check_dns_records(config)
            show_dns_table(dns_results)
            
            # Initialization complete
            print("\nMail forwarder initialized successfully")
            print("Services will be managed by supervisord")
            
            # We don't need to keep the entrypoint script running indefinitely
            # since supervisord is managing the services
            return 0
        else:
            logger.error("Initialization failed, exiting")
            return 1
    except Exception as e:
        logger.error(f"Error: {e}")
        return 1

def show_config():
    """Show the current configuration in a tabular format."""
    try:
        config = from_environment()
        show_config_table(config)  # Reuse the table format for consistency
        return 0
    except Exception as e:
        logger.error(f"Error showing configuration: {e}")
        return 1

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Mail Forwarder Container")
    parser.add_argument("command", choices=["run", "config", "initialize"], 
                        help="Command to execute")
    
    args = parser.parse_args()
    
    if args.command == "run":
        return_code = run()
    elif args.command == "config":
        return_code = show_config()
    elif args.command == "initialize":
        return_code = run()  # Same as run
    else:
        logger.error(f"Unknown command: {args.command}")
        return_code = 1
    
    sys.exit(return_code)

if __name__ == "__main__":
    main() 