# Docker Mail Forwarder and SMTP Relay

A Docker-based mail forwarder and SMTP relay server that is fully configurable via environment variables. It supports forwarding emails to real mailboxes/addresses, SMTP relay with authentication, and automatic ACME certificate management (Let's Encrypt).

## Features

- **Multiple Domain Support**: Automatically detects domains from forwarding rules
- **Mail Forwarding**: Forward emails using patterns or wildcards to external addresses
- **SMTP Relay**: Enable authenticated SMTP relay for sending mail through the container
- **TLS Encryption**: Automatic ACME certificate management for secure mail transport
- **DKIM Support**: DomainKeys Identified Mail for enhanced deliverability (enabled by default)
- **DNS Verification**: Automatic verification of DNS records (MX, DKIM, PTR) at startup
- **Flexible ACME Verification**: Support for TLS-ALPN and HTTP-01 challenge methods
- **Secure Defaults**: Comes with secure defaults that can be overridden as needed
- **Maintenance-Free**: Once configured, requires no ongoing maintenance

## Quick Start

```bash
docker run -d \
  --name mail-forwarder \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -e MAIL_HOSTNAME=mail.example.com \
  -e MAIL_FORWARDS="user@example.com:external@gmail.com;*@example.org:catch-all@gmail.com" \
  -e SMTP_USERS="user1:password1;user2:password2" \
  -e ACME_EMAIL=admin@example.com \
  -v dkim-keys:/var/mail/dkim \
  -v letsencrypt-data:/etc/letsencrypt \
  ghcr.io/jkaberg/mail-forwarder
```

> Note: The container uses TLS-ALPN verification by default (port 587). If you need HTTP-01 verification instead, add `-e ACME_METHOD=http -p 80:80`.

## Configuration Options

### Basic Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `MAIL_FORWARDS` | Semicolon-separated list of mail forwards in format `source@domain:destination@domain` | Empty |
| `MAIL_HOSTNAME` | FQDN of the mail server | `mail.example.com` |
| `ACME_EMAIL` | Email address for Let's Encrypt notifications | `admin@primarydomain` |
| `TZ` | Timezone for the server | `UTC` |
| `VERIFY_DNS` | Enable DNS verification at startup | `true` |

> **Note:** Domains are automatically extracted from `MAIL_FORWARDS`. You no longer need to specify `MAIL_DOMAINS` separately.

### Let's Encrypt Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `ACME_METHOD` | Challenge method for Let's Encrypt verification (`tls-alpn` or `http`) | `tls-alpn` |
| `ALPN_PORT` | Port to use for TLS-ALPN verification | `587` |
| `RENEWAL_DAYS` | Renew certificates when expiration is within this many days | `7` |

### Mail Forwarding

The `MAIL_FORWARDS` variable supports various patterns:

- `user@domain.com:external@example.com` - Forward email for specific address
- `*@domain.com:external@example.com` - Forward all email for domain (catch-all)
- `prefix*@domain.com:external@example.com` - Forward all email with prefix
- `*suffix@domain.com:external@example.com` - Forward all email with suffix

### SMTP Authentication

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `SMTP_USERS` | Semicolon-separated list of SMTP users in format `username:password` | Empty |
| `ENABLE_SMTP_AUTH` | Enable SMTP authentication | `true` |

### SMTP Relay Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `SMTP_RELAY_HOST` | Hostname of upstream SMTP relay | Empty |
| `SMTP_RELAY_PORT` | Port of upstream SMTP relay | `25` |
| `SMTP_RELAY_USERNAME` | Username for upstream SMTP relay | Empty |
| `SMTP_RELAY_PASSWORD` | Password for upstream SMTP relay | Empty |

### Security Settings

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `ENABLE_TLS` | Enable TLS for incoming connections | `true` |
| `ENABLE_DKIM` | Enable DKIM signing | `true` |
| `SMTP_NETWORKS` | Networks allowed to relay without authentication | `127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16` |

### ACME/Let's Encrypt 

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `ACME_EMAIL` | Email address for Let's Encrypt notifications | `admin@primarydomain` |
| `TLS_CERT_DOMAIN` | Domain for TLS certificate | Value of `$MAIL_HOSTNAME` |

## Volume Mounts

The container uses the following volume mounts:

- `/etc/letsencrypt`: For persisting ACME certificates
- `/var/mail/dkim`: For persisting DKIM keys

Since this container only forwards mail and doesn't store it, we only need to persist the TLS certificates and DKIM keys. No actual mail data is stored between restarts.

## Let's Encrypt

### TLS-ALPN Challenge (Default)

The TLS-ALPN challenge method uses your existing SMTP TLS port for domain verification. This is ideal for mail servers because:

- **Uses mail ports you already expose**: No need for additional ports
- **No additional ports required**: Perfect when you can't expose HTTP ports
- **More secure than HTTP**: Uses encrypted channel for verification

To use TLS-ALPN challenge (this is the default):

```bash
# Default configuration (uses port 587)
-e ACME_METHOD=tls-alpn

# Or to specify a different port (e.g., 465)
-e ACME_METHOD=tls-alpn
-e ALPN_PORT=465
```

**Important Note about Port Usage**: During the certificate renewal process, Postfix is briefly paused to allow Certbot to bind to the mail port for verification. This means there will be a very brief outage (typically a few seconds) during certificate renewal. This only happens when a certificate actually needs to be renewed (by default, when it's within 7 days of expiration).

### HTTP-01 Challenge (Alternative)

The HTTP-01 challenge is the traditional method and requires:
- Port 80 to be accessible from the internet
- No other service using port 80 on the host

To use HTTP-01 challenge, add these flags:

```bash
-e ACME_METHOD=http
-p 80:80
```

## Certificate Renewal

Let's Encrypt certificates are valid for 90 days. The container is configured to:

1. **Check certificates twice daily** (at midnight and noon)
2. **Only perform a renewal if the certificate is close to expiration** (within 7 days by default)
3. **Automatically apply renewed certificates** to Postfix without container restarts

This approach is much more efficient than attempting to renew the certificates on every check. You can customize the renewal threshold with the `RENEWAL_DAYS` environment variable:

```bash
# Wait until certificate is about to expire in 14 days
-e RENEWAL_DAYS=14
```

## DNS Configuration

⚠️ **IMPORTANT: Proper DNS configuration is REQUIRED for reliable mail delivery** ⚠️

The container performs DNS verification at startup and will show you exactly what records need to be configured. It also creates a summary file at `/opt/dns_requirements.txt` inside the container that you can reference anytime.

To view this file:
```bash
docker exec mail-forwarder cat /opt/dns_requirements.txt
```

For each domain you want to handle mail for, you need to set up:

### 1. MX Records

For each domain, create an MX record pointing to your mail server:

```
example.com. IN MX 10 mail.example.com.
```

### 2. DKIM Records (Required for deliverability)

DKIM is enabled by default. The container will generate the keys and output the required DNS TXT records in both the logs and the DNS requirements summary file. The format will be:

```
Name: mail._domainkey.example.com
Value: v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...
```

### 3. PTR Record (Reverse DNS)

Set up a proper PTR record for your server's IP address pointing to your `MAIL_HOSTNAME`. This is critical for deliverability as many receiving mail servers will reject emails from IPs without proper reverse DNS.

To set up a PTR record:
1. Contact your hosting provider or server provider (PTR records are usually managed by them)
2. Request that they set up a PTR record for your IP address pointing to your `MAIL_HOSTNAME`
3. The format should be: `your-ip-address → mail.example.com`

### 4. SPF Records (Recommended)

While optional, SPF records are strongly recommended for improved deliverability:

```
example.com. IN TXT "v=spf1 ip4:YOUR_SERVER_IP ~all"
```

### Mail Delivery Will Fail Without Proper DNS

Many email providers (Gmail, Outlook, Yahoo, etc.) require proper DNS configuration before they'll accept incoming mail. Without these records, your emails may be:
- Rejected outright
- Marked as spam
- Silently discarded

## Mail Delivery Considerations

### Will Mail Forwarding Break Anything?

This mail forwarder is designed to handle forwarding reliably, but here are some important considerations:

1. **SPF Alignment**: When forwarding, the envelope sender changes, which can break SPF alignment. Our implementation:
   - Preserves the original From header
   - Uses DKIM signing to help authenticate messages despite SPF issues

2. **Destination Mail Servers**: Some receiving mail servers are more strict than others:
   - Gmail, Office 365, etc. may accept forwarded mail if DKIM is intact
   - Stricter servers might reject forwarded messages due to SPF failures

3. **Best Practices**:
   - Always enable DKIM (default in this container)
   - Make sure your server has proper PTR/reverse DNS records
   - Set up your server on a clean IP address without spam history

For best results, use this forwarder with trusted receiving email services that properly implement modern email standards.

## Examples

### Basic Mail Forwarding with TLS-ALPN (Default)

```bash
docker run -d \
  --name mail-forwarder \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -e MAIL_HOSTNAME=mail.example.com \
  -e MAIL_FORWARDS="user@example.com:personal@gmail.com;*@example.com:catch-all@gmail.com" \
  -e ACME_EMAIL=admin@example.com \
  -v dkim-keys:/var/mail/dkim \
  -v letsencrypt-data:/etc/letsencrypt \
  jkaberg/mail-forwarder
```

### Multiple Domains with HTTP-01 Challenge

```bash
docker run -d \
  --name mail-forwarder \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -p 80:80 \
  -e MAIL_HOSTNAME=mail.example.com \
  -e MAIL_FORWARDS="user@example.com:personal@gmail.com;*@example.org:org-emails@gmail.com;admin@example.net:admin@gmail.com" \
  -e ACME_METHOD=http \
  -e ACME_EMAIL=admin@example.com \
  -v dkim-keys:/var/mail/dkim \
  -v letsencrypt-data:/etc/letsencrypt \
  jkaberg/mail-forwarder
```

### SMTP Authentication with TLS-ALPN using Port 465

```bash
docker run -d \
  --name mail-forwarder \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -e MAIL_HOSTNAME=mail.example.com \
  -e MAIL_FORWARDS="user@example.com:personal@gmail.com" \
  -e SMTP_USERS="john:password123;jane:securepassword" \
  -e ACME_EMAIL=admin@example.com \
  -e ACME_METHOD=tls-alpn \
  -e ALPN_PORT=465 \
  -e RENEWAL_DAYS=14 \
  -v dkim-keys:/var/mail/dkim \
  -v letsencrypt-data:/etc/letsencrypt \
  jkaberg/mail-forwarder
```

## Maintenance-Free Operation

Once properly configured, the mail forwarder is designed to be maintenance-free:

- Certificates are automatically renewed via Let's Encrypt when within 7 days of expiration
- Mail forwarding rules are applied at startup from environment variables
- DNS configuration is verified at startup for proper setup
- All services are monitored by Supervisor and automatically restarted if they fail

The only ongoing maintenance would be:
- Occasional image updates for security patches (can be automated with Watchtower)
- DNS record updates if you change your configuration

## Building the Image

```bash
git clone https://github.com/jkaberg/dockerfiles/mail-forwarder.git
cd mail-forwarder
docker build -t jkaberg/mail-forwarder .
```

## Security Considerations

- The mail forwarder is configured with secure defaults
- SMTP authentication is enabled by default and uses strong encryption
- TLS is enabled by default for secure communication
- DKIM is enabled by default for better deliverability

## License

This project is licensed under the MIT License - see the LICENSE file for details. 