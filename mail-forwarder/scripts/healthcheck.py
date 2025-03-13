#!/usr/bin/env python3
"""
Health check for the mail forwarder container.
Checks the status of all required services.
"""

import os
import sys
import logging
import subprocess
import socket

# Configure logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('healthcheck')

def check_process_running(process_name):
    """Check if a process is running."""
    try:
        output = subprocess.check_output(["pgrep", process_name], universal_newlines=True)
        return len(output.strip()) > 0
    except subprocess.CalledProcessError:
        return False

def check_port_listening(port):
    """Check if a port is listening."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex(('127.0.0.1', port))
        sock.close()
        return result == 0
    except Exception:
        return False

def check_postfix():
    """Check if Postfix is running properly."""
    # Check if process is running
    if not check_process_running("master"):
        logger.error("Postfix master process is not running")
        return False
    
    # Check mail queue
    try:
        output = subprocess.check_output(["mailq"], universal_newlines=True)
        if "Mail queue is empty" in output or "Queue is empty" in output:
            logger.info("Mail queue is empty")
        else:
            logger.warning(f"Mail queue has items: {output.strip()}")
        
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to check mail queue: {e}")
        return False

def check_opendkim():
    """Check if OpenDKIM is running properly."""
    # Check if process is running
    if not check_process_running("opendkim"):
        logger.error("OpenDKIM process is not running")
        return False
    
    # Check if OpenDKIM socket exists
    if not os.path.exists("/var/run/opendkim/opendkim.sock"):
        logger.error("OpenDKIM socket does not exist")
        return False
    
    return True

def check_fail2ban():
    """Check if Fail2ban is running properly."""
    # Check if process is running
    if not check_process_running("fail2ban-server"):
        logger.error("Fail2ban server is not running")
        return False
    
    # Check if Fail2ban is responding
    try:
        output = subprocess.check_output(["fail2ban-client", "ping"], universal_newlines=True)
        if "pong" in output.lower():
            logger.info("Fail2ban is responding")
            return True
        else:
            logger.error(f"Fail2ban is not responding properly: {output.strip()}")
            return False
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to check Fail2ban status: {e}")
        return False

def check_smtp_ports():
    """Check if SMTP ports are listening."""
    ports_to_check = [25, 465, 587]
    all_listening = True
    
    for port in ports_to_check:
        if check_port_listening(port):
            logger.info(f"Port {port} is listening")
        else:
            logger.error(f"Port {port} is not listening")
            all_listening = False
    
    return all_listening

def run_healthcheck():
    """Run all health checks."""
    checks = [
        ("Postfix", check_postfix),
        ("OpenDKIM", check_opendkim),
        ("Fail2ban", check_fail2ban),
        ("SMTP ports", check_smtp_ports),
    ]
    
    all_healthy = True
    for name, check_func in checks:
        try:
            logger.info(f"Checking {name}...")
            if check_func():
                logger.info(f"{name} check passed")
            else:
                logger.error(f"{name} check failed")
                all_healthy = False
        except Exception as e:
            logger.error(f"Error during {name} check: {e}")
            all_healthy = False
    
    return all_healthy

if __name__ == "__main__":
    try:
        healthy = run_healthcheck()
        if healthy:
            logger.info("All health checks passed")
            sys.exit(0)
        else:
            logger.error("One or more health checks failed")
            sys.exit(1)
    except Exception as e:
        logger.error(f"Error during health check: {e}")
        sys.exit(1) 