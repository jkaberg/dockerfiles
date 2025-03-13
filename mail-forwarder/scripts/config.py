#!/usr/bin/env python3
"""
Configuration management for the mail forwarder.
Handles parsing and validating environment variables into a structured configuration.
"""

import os
import re
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('config')

@dataclass
class ForwardingRule:
    """Represents a mail forwarding rule."""
    source: str
    destination: str
    is_wildcard: bool = False

    def __post_init__(self):
        # Validate source is a valid email or wildcard
        if self.is_wildcard:
            if not re.match(r'^(\*|\*\.[^@\s]+)@[^@\s]+\.[^@\s]+$', self.source):
                raise ValueError(f"Invalid wildcard format: {self.source}")
        elif not re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', self.source):
            raise ValueError(f"Invalid source email: {self.source}")
        
        # Validate destination is a valid email
        if not re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', self.destination):
            raise ValueError(f"Invalid destination email: {self.destination}")
    
    @property
    def domain(self) -> str:
        """Extract the domain from the source email."""
        return self.source.split('@')[1] if '@' in self.source else None

@dataclass
class SRSConfig:
    """Configuration for Sender Rewriting Scheme (SRS)."""
    enabled: bool = True
    secret: str = ""
    domain: Optional[str] = None  # If None, will use SMTP hostname
    exclude_domains: Set[str] = field(default_factory=set)
    
    def __post_init__(self):
        # Generate a random secret if one isn't provided and SRS is enabled
        if self.enabled and not self.secret:
            import secrets
            import string
            alphabet = string.ascii_letters + string.digits
            self.secret = ''.join(secrets.choice(alphabet) for _ in range(32))
            logger.info("Generated random SRS secret")

@dataclass
class DKIMConfig:
    """Configuration for DKIM signing."""
    enabled: bool = True
    selector: str = "mail"
    key_size: int = 2048
    domains: Set[str] = field(default_factory=set)

@dataclass
class TLSConfig:
    """Configuration for TLS certificates."""
    enabled: bool = True
    email: str = ""
    domains: Set[str] = field(default_factory=set)
    challenge_type: str = "tls-alpn"  # "tls-alpn" or "http"
    staging: bool = False
    renewal_days: int = 30
    use_letsencrypt: bool = True
    key_size: int = 2048
    params_bits: int = 2048
    security_level: str = "may"
    protocols: str = "!SSLv2, !SSLv3"
    ciphers: str = "high"

@dataclass
class SMTPConfig:
    """Configuration for SMTP settings."""
    hostname: str = "mail.example.com"
    relay_host: Optional[str] = None
    relay_port: int = 25
    relay_username: Optional[str] = None
    relay_password: Optional[str] = None
    use_tls: bool = True
    helo_name: Optional[str] = None  # If None, will use hostname
    
    # Ports to enable
    enable_smtp: bool = True
    enable_submission: bool = True
    enable_smtps: bool = True
    
    def __post_init__(self):
        # Use hostname for helo_name if not specified
        if not self.helo_name:
            self.helo_name = self.hostname

@dataclass
class SecurityConfig:
    """Configuration for security settings."""
    fail2ban_enabled: bool = True
    max_attempts: int = 5
    ban_time: int = 3600
    find_time: int = 600

@dataclass
class Configuration:
    """Main configuration container."""
    debug: bool = False
    smtp: SMTPConfig = field(default_factory=SMTPConfig)
    dkim: DKIMConfig = field(default_factory=DKIMConfig)
    tls: TLSConfig = field(default_factory=TLSConfig)
    security: SecurityConfig = field(default_factory=SecurityConfig)
    srs: SRSConfig = field(default_factory=SRSConfig)
    forwarding_rules: List[ForwardingRule] = field(default_factory=list)

    def validate(self) -> None:
        """Validate the configuration and set smart defaults."""
        # Basic validation
        if not self.smtp.hostname:
            raise ValueError("SMTP hostname cannot be empty")
        
        # Check if there are any rules
        if not self.forwarding_rules:
            raise ValueError("No forwarding rules defined")
        
        # Extract all domains from forwarding rules
        all_domains = set()
        for rule in self.forwarding_rules:
            domain = rule.domain
            if domain:
                all_domains.add(domain)
        
        # Add the hostname domain to the list of all domains
        hostname_domain = self.smtp.hostname.split('.', 1)[-1] if '.' in self.smtp.hostname else self.smtp.hostname
        all_domains.add(hostname_domain)
        
        # Set DKIM domains if not explicitly set
        if not self.dkim.domains and self.dkim.enabled:
            self.dkim.domains = all_domains
            logger.info(f"Auto-configuring DKIM for domains: {', '.join(all_domains)}")
        
        # Set TLS domains if not explicitly set
        if not self.tls.domains and self.tls.enabled:
            # Add the SMTP hostname (for the mail server itself)
            self.tls.domains.add(self.smtp.hostname)
            
            # Add any domains from forwarding rules that might need certificates
            # Only add domains we might receive mail for
            self.tls.domains.update(all_domains)
            logger.info(f"Auto-configuring TLS for domains: {', '.join(self.tls.domains)}")
        
        # Set SRS domain if not explicitly set
        if self.srs.enabled and not self.srs.domain:
            self.srs.domain = self.smtp.hostname
            logger.info(f"Auto-configuring SRS domain: {self.srs.domain}")
        
        # TLS validation
        if self.tls.enabled and not self.tls.email:
            raise ValueError("TLS is enabled but no email provided for Let's Encrypt")
        
        # Relay validation
        if self.smtp.relay_host:
            if self.smtp.relay_username and not self.smtp.relay_password:
                raise ValueError("Relay username provided but no password")

def parse_forwarding_rules(env_vars: Dict[str, str]) -> List[ForwardingRule]:
    """Parse forwarding rules from environment variables."""
    rules = []

    # Parse FORWARD_* variables
    pattern = re.compile(r'^FORWARD_(.+)$')
    for key, value in env_vars.items():
        match = pattern.match(key)
        if match:
            source = match.group(1).replace('__', '@')
            destinations = [dest.strip() for dest in value.split(',')]
            
            # Handle wildcard
            is_wildcard = source.startswith('*@') or source.startswith('*.')
            
            # Add a rule for each destination
            for dest in destinations:
                try:
                    rule = ForwardingRule(source=source, destination=dest, is_wildcard=is_wildcard)
                    rules.append(rule)
                except ValueError as e:
                    logger.warning(f"Skipping invalid rule: {e}")
    
    return rules

def parse_bool(value: str) -> bool:
    """Parse a string into a boolean value."""
    return str(value).lower() in ('true', 'yes', '1', 'on')

def parse_int(value: str, default: int) -> int:
    """Parse a string into an integer value."""
    try:
        return int(value)
    except (ValueError, TypeError):
        return default

def from_environment() -> Configuration:
    """Load configuration from environment variables."""
    env = os.environ
    
    # Create base configuration
    config = Configuration(
        debug=parse_bool(env.get('DEBUG', 'false')),
    )
    
    # SMTP Configuration
    config.smtp = SMTPConfig(
        hostname=env.get('SMTP_HOSTNAME', 'mail.example.com'),
        relay_host=env.get('SMTP_RELAY_HOST'),
        relay_port=parse_int(env.get('SMTP_RELAY_PORT', '25'), 25),
        relay_username=env.get('SMTP_RELAY_USERNAME'),
        relay_password=env.get('SMTP_RELAY_PASSWORD'),
        use_tls=parse_bool(env.get('SMTP_RELAY_USE_TLS', 'true')),
        helo_name=env.get('SMTP_HELO_NAME'),  # Will default to hostname if None
        enable_smtp=parse_bool(env.get('ENABLE_SMTP', 'true')),
        enable_submission=parse_bool(env.get('ENABLE_SUBMISSION', 'true')),
        enable_smtps=parse_bool(env.get('ENABLE_SMTPS', 'true')),
    )
    
    # Parse forwarding rules first so we can derive domains
    config.forwarding_rules = parse_forwarding_rules(env)
    
    # Extract domains from rules for smart defaults
    domains_from_rules = set()
    for rule in config.forwarding_rules:
        domain = rule.domain
        if domain:
            domains_from_rules.add(domain)
    
    # DKIM Configuration
    dkim_domains = set()
    if env.get('DKIM_DOMAINS'):
        dkim_domains = {domain.strip() for domain in env.get('DKIM_DOMAINS', '').split(',')}
    
    config.dkim = DKIMConfig(
        enabled=parse_bool(env.get('DKIM_ENABLED', 'true')),
        selector=env.get('DKIM_SELECTOR', 'mail'),
        key_size=parse_int(env.get('DKIM_KEY_SIZE', '2048'), 2048),
        domains=dkim_domains,
    )
    
    # TLS Configuration
    tls_domains = set()
    if env.get('TLS_DOMAINS'):
        tls_domains = {domain.strip() for domain in env.get('TLS_DOMAINS', '').split(',')}
    
    config.tls = TLSConfig(
        enabled=parse_bool(env.get('TLS_ENABLED', 'true')),
        email=env.get('TLS_EMAIL', ''),
        domains=tls_domains,
        challenge_type=env.get('TLS_CHALLENGE_TYPE', 'tls-alpn').lower(),
        staging=parse_bool(env.get('TLS_STAGING', 'false')),
        renewal_days=parse_int(env.get('TLS_RENEWAL_DAYS', '30'), 30),
        use_letsencrypt=parse_bool(env.get('TLS_USE_LETSENCRYPT', 'true')),
        key_size=parse_int(env.get('TLS_KEY_SIZE', '2048'), 2048),
        params_bits=parse_int(env.get('TLS_PARAMS_BITS', '2048'), 2048),
        security_level=env.get('TLS_SECURITY_LEVEL', 'may'),
        protocols=env.get('TLS_PROTOCOLS', '!SSLv2, !SSLv3'),
        ciphers=env.get('TLS_CIPHERS', 'high'),
    )
    
    # SRS Configuration
    srs_exclude_domains = set()
    if env.get('SRS_EXCLUDE_DOMAINS'):
        srs_exclude_domains = {domain.strip() for domain in env.get('SRS_EXCLUDE_DOMAINS', '').split(',')}
    
    config.srs = SRSConfig(
        enabled=parse_bool(env.get('SRS_ENABLED', 'true')),
        secret=env.get('SRS_SECRET', ''),
        domain=env.get('SRS_DOMAIN'),  # Will default to SMTP hostname if None
        exclude_domains=srs_exclude_domains,
    )
    
    # Security Configuration
    config.security = SecurityConfig(
        fail2ban_enabled=parse_bool(env.get('FAIL2BAN_ENABLED', 'true')),
        max_attempts=parse_int(env.get('FAIL2BAN_MAX_ATTEMPTS', '5'), 5),
        ban_time=parse_int(env.get('FAIL2BAN_BAN_TIME', '3600'), 3600),
        find_time=parse_int(env.get('FAIL2BAN_FIND_TIME', '600'), 600),
    )
    
    # Validate the configuration and set smart defaults
    try:
        config.validate()
    except ValueError as e:
        logger.error(f"Configuration error: {e}")
        raise
    
    return config

if __name__ == "__main__":
    # Test configuration parsing
    try:
        config = from_environment()
        logger.info("Configuration loaded successfully:")
        logger.debug(f"SMTP hostname: {config.smtp.hostname}")
        logger.debug(f"SMTP helo_name: {config.smtp.helo_name}")
        logger.debug(f"Forwarding rules: {len(config.forwarding_rules)}")
        for rule in config.forwarding_rules:
            logger.debug(f"  {rule.source} -> {rule.destination}")
        logger.debug(f"DKIM domains: {', '.join(config.dkim.domains)}")
        logger.debug(f"TLS domains: {', '.join(config.tls.domains)}")
    except Exception as e:
        logger.error(f"Error: {e}") 