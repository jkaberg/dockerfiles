#!/bin/bash
set -e

# Install OpenDKIM and its dependencies
apt-get update && apt-get install -y --no-install-recommends opendkim opendkim-tools && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure OpenDKIM
cat > /etc/opendkim.conf <<EOF
# Log to syslog
Syslog                  yes
SyslogSuccess           yes

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

mkdir -p /var/spool/postfix/opendkim
chown opendkim:postfix /var/spool/postfix/opendkim

mkdir -p /etc/opendkim/keys
chown -R opendkim:opendkim /etc/opendkim

# Add postfix user to opendkim group
usermod -a -G opendkim postfix

# Configure trusted hosts
mkdir -p /etc/opendkim
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

# Process each domain
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
for domain in "${DOMAIN_ARRAY[@]}"; do
    echo "Configuring DKIM for domain: $domain"
    
    # Create directories for the domain
    mkdir -p "/var/mail/dkim/$domain"
    
    # Generate keys if they don't exist
    if [ ! -f "/var/mail/dkim/$domain/mail.private" ]; then
        opendkim-genkey -b 2048 -d "$domain" -s mail -D "/var/mail/dkim/$domain"
        chown -R opendkim:opendkim "/var/mail/dkim/$domain"
        chmod 600 "/var/mail/dkim/$domain/mail.private"
    fi
    
    # Add to key table
    echo "mail._domainkey.$domain $domain:mail:/var/mail/dkim/$domain/mail.private" >> /etc/opendkim/key.table
    
    # Add to signing table
    echo "*@$domain mail._domainkey.$domain" >> /etc/opendkim/signing.table
    
    # Output the DNS TXT record needed
    echo "============================================================="
    echo "DKIM DNS TXT Record for $domain:"
    echo "Name: mail._domainkey.$domain"
    echo "Value: $(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'p=.*"' | tr -d '"')"
    echo "============================================================="
done

# Configure Postfix to use OpenDKIM
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"
postconf -e "non_smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"

# Start OpenDKIM service
service opendkim restart

echo "DKIM configuration completed." 