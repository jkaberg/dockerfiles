# Python-based Mail Forwarder

A comprehensive Docker container for email forwarding with modern security features and easy deployment.

## Features

- **Mail Forwarding**
  - Forward emails from multiple source domains to external addresses
  - Support for wildcard/catch-all forwarding (e.g., *@example.com)
  - Detailed forwarding rule configuration via environment variables
  - SMTP authentication for outbound mail
  - SRS (Sender Rewriting Scheme) for proper SPF validation of forwarded emails

- **Email Authentication**
  - DKIM signing for all outgoing emails
  - Automatic DKIM key generation and management
  - Support for SPF and DMARC via proper DNS configuration
  - Detailed DNS verification and reporting

- **TLS/Security Features**
  - Automatic TLS certificate acquisition and renewal via Let's Encrypt
  - Support for both TLS-ALPN and HTTP-01 challenge methods
  - Proper certificate deployment to mail services
  - Fail2ban integration for brute-force protection

- **Container-based Solution**
  - Dockerfile based on Debian Bullseye (slim)
  - Docker Compose file for easy deployment
  - Multi-platform support (amd64, arm64)

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/jkaberg/mail-forwarder.git
   cd mail-forwarder
   ```

2. Edit the `docker-compose.yml` file to configure your mail forwarder:
   - Set your domain name (`SMTP_HOSTNAME`)
   - Configure forwarding rules
   - Set your email for Let's Encrypt (`ACME_EMAIL`)

3. Start the container:
   ```bash
   docker-compose up -d
   ```

4. Check the logs to ensure everything is working:
   ```bash
   docker-compose logs -f
   ```

## Configuration

### Environment Variables

#### Basic Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `SMTP_HOSTNAME` | The hostname of your mail server | `mail.example.com` |
| `SMTP_HELO_NAME` | The HELO name to use (defaults to hostname) | Same as `SMTP_HOSTNAME` |
| `DEBUG` | Enable debug logging | `false` |

#### Forwarding Rules

Forwarding rules are defined using the `FORWARD_RULES` environment variable with a concise syntax:

```
FORWARD_RULES=user@example.com:external@gmail.com;*@example.com:catchall@gmail.com
```

In this format:
- Source and destination are separated by a colon (`:`)
- Multiple rules are separated by a semicolon (`;`)
- Wildcard/catch-all rules use the `*@domain.tld` format

Examples:
- Standard forwarding: `user@domain.tld:destination@otherdomain.tld`
- Catch-all forwarding: `*@domain.tld:destination@otherdomain.tld`
- Multiple rules: `user1@domain.tld:dest1@other.tld;user2@domain.tld:dest2@other.tld`

#### DKIM Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DKIM_ENABLED` | Enable DKIM signing (enabled by default) | `true` |
| `DKIM_SELECTOR` | DKIM selector to use | `mail` |
| `DKIM_KEY_SIZE` | Size of DKIM keys in bits | `2048` |
| `DKIM_DOMAINS` | Comma-separated list of domains to sign (defaults to all forwarding domains) | All domains from forwarding rules |

#### TLS Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `TLS_ENABLED` | Enable TLS certificate management (enabled by default) | `true` |
| `ACME_EMAIL` | Email address for Let's Encrypt | `""` (required if TLS is enabled) |
| `TLS_DOMAINS` | Comma-separated list of domains for certificates (defaults to SMTP_HOSTNAME) | `SMTP_HOSTNAME` |
| `TLS_CHALLENGE_TYPE` | Challenge type for Let's Encrypt (`http` or `tls-alpn`) | `tls-alpn` |
| `TLS_STAGING` | Use Let's Encrypt staging environment | `false` |
| `TLS_RENEWAL_DAYS` | Days before expiry to renew certificates | `7` |

##### Certificate Renewal Process

The mail-forwarder uses a robust approach for handling certificate renewals:

1. A daily cron job checks for certificates that are within 7 days of expiry
2. When certificates need to be renewed, the process:
   - Temporarily stops Postfix to free port 587 for validation
   - Renews ALL certificates in a single downtime window
   - Restarts Postfix to resume email operations

This approach ensures that:
- The mail server maintains valid certificates with minimal downtime
- All renewals happen in a single maintenance window
- The renewal process is fully automated via cron
- The downtime only occurs when certificates actually need renewal (within 7 days of expiry)

The renewal cron job runs at a randomized time each day to distribute load on Let's Encrypt servers.

#### SMTP Relay Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `SMTP_RELAY_HOST` | Hostname of SMTP relay server | `null` (no relay) |
| `SMTP_RELAY_PORT` | Port of SMTP relay server | `25` |
| `SMTP_RELAY_USERNAME` | Username for SMTP relay authentication | `null` |
| `SMTP_RELAY_PASSWORD` | Password for SMTP relay authentication | `null` |
| `SMTP_RELAY_USE_TLS` | Use TLS for SMTP relay | `true` |

#### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `FAIL2BAN_ENABLED` | Enable Fail2ban for brute-force protection (enabled by default) | `true` |
| `FAIL2BAN_MAX_ATTEMPTS` | Maximum number of failed attempts before ban | `5` |
| `FAIL2BAN_BAN_TIME` | Ban time in seconds | `3600` (1 hour) |
| `FAIL2BAN_FIND_TIME` | Time window for failed attempts in seconds | `600` (10 minutes) |

#### SRS Configuration (Sender Rewriting Scheme)

SRS is used to rewrite the envelope sender address in forwarded email to ensure proper SPF validation and return path handling.

| Variable | Description | Default |
|----------|-------------|---------|
| `SRS_ENABLED` | Enable SRS for forwarded emails (enabled by default) | `true` |
| `SRS_SECRET` | Secret key for SRS signatures | Randomly generated on first start |
| `SRS_DOMAIN` | Domain to use for SRS rewriting | Same as `SMTP_HOSTNAME` |
| `SRS_EXCLUDE_DOMAINS` | Comma-separated list of domains to exclude from SRS | `""` (none) |

#### Port Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `ENABLE_SMTP` | Enable SMTP on port 25 | `true` |
| `ENABLE_SUBMISSION` | Enable Submission on port 587 | `true` |
| `ENABLE_SMTPS` | Enable SMTPS on port 465 | `true` |