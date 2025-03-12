#!/bin/bash
set -e

# Make sure we have the latest environment variables
if [ -f /etc/environment ]; then
    source /etc/environment
fi

# Configure OpenDKIM
cat > /etc/opendkim.conf <<EOF
# Log to stdout/stderr instead of syslog
Syslog                  no
LogWhy                  yes

# Required to use local socket with postfix
Mode                    sv
AutoRestart             yes
AutoRestartRate         10/1M
Background              yes
DNSTimeout              5
SignatureAlgorithm      rsa-sha256
Socket                  local:/var/spool/postfix/opendkim/opendkim.sock
PidFile                 /var/run/opendkim/opendkim.pid
UMask                   022
UserID                  opendkim:opendkim
TemporaryDirectory      /var/tmp

# Signing table lists the keypairs to use for each domain
KeyTable                refile:/etc/opendkim/key.table
SigningTable            refile:/etc/opendkim/signing.table

# External ignore hosts (trusted hosts)
ExternalIgnoreList      /etc/opendkim/trusted.hosts
InternalHosts           /etc/opendkim/trusted.hosts
EOF

# Create needed directories
mkdir -p /var/run/opendkim
chown opendkim:opendkim /var/run/opendkim

# Create opendkim directory in postfix chroot
mkdir -p /var/spool/postfix/opendkim
chown opendkim:postfix /var/spool/postfix/opendkim
chmod 750 /var/spool/postfix/opendkim

mkdir -p /etc/opendkim/keys
chown -R opendkim:opendkim /etc/opendkim

# Add postfix user to opendkim group and vice versa to ensure socket permissions work
usermod -a -G opendkim postfix
usermod -a -G postfix opendkim

# Configure trusted hosts
cat > /etc/opendkim/trusted.hosts <<EOF
127.0.0.1
localhost
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
EOF

# Create key tables
touch /etc/opendkim/key.table
touch /etc/opendkim/signing.table
chown opendkim:opendkim /etc/opendkim/key.table /etc/opendkim/signing.table
chmod 644 /etc/opendkim/key.table /etc/opendkim/signing.table

# Display DKIM configuration in a table
display_dkim_config() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                           DKIM CONFIGURATION                         "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    printf "%-25s %-15s %-27s\n" "DOMAIN" "STATUS" "SELECTOR"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    local all_success=true
    local domain_count=0
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    
    # Count domains
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain_count=$((domain_count+1))
        if [ -f "/var/mail/dkim/$domain/mail.private" ]; then
            # Use printf with -e to properly interpret color codes
            printf "%-25s " "$domain"
            printf "%-15s " "✅ Active"
            printf "%-27s\n" "mail._domainkey.$domain"
        else
            printf "%-25s " "$domain"
            printf "%-15s " "⚠️ Missing"
            printf "%-27s\n" "mail._domainkey.$domain"
            all_success=false
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # If no domains were processed, show warning
    if [ $domain_count -eq 0 ]; then
        echo "⚠️ No domains configured for DKIM. Configure MAIL_DOMAINS environment variable."
    elif [ "$all_success" = "true" ]; then
        echo "✅ DKIM configuration complete for all domains"
    else
        echo "⚠️ Some DKIM keys are missing. Check DNS records after container restarts."
    fi
}

# Main
echo "Configuring DKIM..."

# Set up DKIM keys for each domain
if [ -z "$MAIL_DOMAINS" ]; then
    echo "No mail domains specified. Cannot configure DKIM."
else
    echo "Configuring DKIM for domains: $MAIL_DOMAINS"
    
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        # Trim any whitespace
        domain=$(echo "$domain" | xargs)
        
        # Skip empty domains
        if [ -z "$domain" ]; then
            continue
        fi
        
        echo "Setting up DKIM for domain: $domain"
        
        # Create directory for domain keys
        mkdir -p "/var/mail/dkim/$domain"
        
        # Generate keys if they don't exist
        if [ ! -f "/var/mail/dkim/$domain/mail.private" ]; then
            echo "Generating DKIM keys for $domain..."
            opendkim-genkey -D "/var/mail/dkim/$domain/" -d "$domain" -s mail
            chown -R opendkim:opendkim "/var/mail/dkim/$domain"
        fi
        
        # Add domain to KeyTable
        if ! grep -q "mail._domainkey.$domain" /etc/opendkim/key.table; then
            echo "mail._domainkey.$domain $domain:mail:/var/mail/dkim/$domain/mail.private" >> /etc/opendkim/key.table
        fi
        
        # Add domain to SigningTable
        if ! grep -q "\\*@$domain" /etc/opendkim/signing.table; then
            echo "*@$domain mail._domainkey.$domain" >> /etc/opendkim/signing.table
        fi
        
        # Add domain to TrustedHosts
        if ! grep -q "^$domain$" /etc/opendkim/trusted.hosts; then
            echo "$domain" >> /etc/opendkim/trusted.hosts
        fi
    done
fi

# Ensure OpenDKIM can read the keys
chown -R opendkim:opendkim /var/mail/dkim
chown opendkim:opendkim /etc/opendkim/key.table /etc/opendkim/signing.table /etc/opendkim/trusted.hosts

# Display DKIM configuration in a table
display_dkim_config

# Configure Postfix to use OpenDKIM
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"
postconf -e "non_smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"

echo "DKIM configuration completed." 