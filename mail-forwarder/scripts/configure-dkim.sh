#!/bin/bash
set -e

# Source our table formatter utility
if [ -f "$(dirname "$0")/table-formatter.sh" ]; then
    source "$(dirname "$0")/table-formatter.sh"
else
    echo "Error: table-formatter.sh not found. Please ensure it's in the same directory as this script."
fi

# Source environment variables
if [ -f "/etc/environment" ]; then
    source /etc/environment
fi

# Initialize variables with defaults if not set
MAIL_DOMAINS=${MAIL_DOMAINS:-""}
ENABLE_DKIM=${ENABLE_DKIM:-"false"}
VERBOSE_MODE=${VERBOSE_MODE:-"false"}

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

# Configure DKIM keys for specified domains
configure_dkim() {
    if [ "$ENABLE_DKIM" != "true" ]; then
        [ "$VERBOSE_MODE" = "true" ] && echo "DKIM is disabled. Set ENABLE_DKIM=true to enable."
        return 0
    fi

    [ "$VERBOSE_MODE" = "true" ] && echo "Configuring DKIM..."

    local domain_count=0
    
    # If no domains specified, check forwarding rules
    if [ -z "$MAIL_DOMAINS" ]; then
        [ "$VERBOSE_MODE" = "true" ] && echo "No domains specified, checking forwarding configuration..."
        if [ -f "/etc/postfix/virtual" ]; then
            FORWARDING_DOMAINS=$(awk -F'@' '{print $2}' /etc/postfix/virtual | awk '{print $1}' | sort -u | grep -v '^$')
            if [ ! -z "$FORWARDING_DOMAINS" ]; then
                MAIL_DOMAINS=$(echo "$FORWARDING_DOMAINS" | tr '\n' ',' | sed 's/,$//')
                [ "$VERBOSE_MODE" = "true" ] && echo "Found domains from forwarding rules: $MAIL_DOMAINS"
            fi
        fi
    fi

    if [ -z "$MAIL_DOMAINS" ]; then
        echo "⚠️  Warning: No mail domains specified for DKIM configuration."
        return 1
    fi

    [ "$VERBOSE_MODE" = "true" ] && echo "Configuring DKIM for domains: $MAIL_DOMAINS"

    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain_count=$((domain_count + 1))
        
        # Skip empty domains
        if [ -z "$domain" ]; then
            continue
        fi

        # Prepare directory
        mkdir -p /var/mail/dkim/$domain

        # Check if key already exists
        if [ ! -f "/var/mail/dkim/$domain/mail.private" ]; then
            echo "Generating DKIM key for domain: $domain"
            
            # Generate key
            openssl genrsa -out /var/mail/dkim/$domain/mail.private 2048 2>/dev/null
            chmod 400 /var/mail/dkim/$domain/mail.private
            
            # Generate public key
            openssl rsa -in /var/mail/dkim/$domain/mail.private -pubout -outform PEM -out /var/mail/dkim/$domain/mail.public 2>/dev/null
            
            # Generate DNS record
            dns_record="v=DKIM1; k=rsa; p=$(grep -v -e '^-' /var/mail/dkim/$domain/mail.public | tr -d '\n')"
            echo "$dns_record" > /var/mail/dkim/$domain/mail.txt
            
            echo "✅ DKIM key generated for $domain"
            echo "🔑 DNS Record: mail._domainkey.$domain. IN TXT \"$dns_record\""
        elif [ "$VERBOSE_MODE" = "true" ]; then
            echo "DKIM key already exists for $domain"
        fi
    done

    # Configure OpenDKIM
    if [ $domain_count -gt 0 ]; then
        # Create KeyTable file
        > /etc/opendkim/KeyTable
        for domain in "${DOMAIN_ARRAY[@]}"; do
            [ -z "$domain" ] && continue
            echo "mail._domainkey.$domain $domain:mail:/var/mail/dkim/$domain/mail.private" >> /etc/opendkim/KeyTable
        done

        # Create SigningTable file
        > /etc/opendkim/SigningTable
        for domain in "${DOMAIN_ARRAY[@]}"; do
            [ -z "$domain" ] && continue
            echo "*@$domain mail._domainkey.$domain" >> /etc/opendkim/SigningTable
        done

        # Update trusted hosts
        > /etc/opendkim/TrustedHosts
        echo "127.0.0.1" >> /etc/opendkim/TrustedHosts
        echo "localhost" >> /etc/opendkim/TrustedHosts
        for domain in "${DOMAIN_ARRAY[@]}"; do
            [ -z "$domain" ] && continue
            echo "*.$domain" >> /etc/opendkim/TrustedHosts
        done

        # restart opendkim
        [ "$VERBOSE_MODE" = "true" ] && echo "Restarting OpenDKIM service..."
        service opendkim restart

        # Display the DKIM status table
        if [ "$VERBOSE_MODE" = "true" ]; then
            create_dkim_table "$MAIL_DOMAINS"
        else
            echo "✅ DKIM configuration complete for $domain_count domain(s)"
        fi
    else
        echo "⚠️  Warning: No domains configured for DKIM"
    fi
}

# Execute the configuration
configure_dkim

# Configure Postfix to use OpenDKIM
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"
postconf -e "non_smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock"

# Only show final message in verbose mode
if [ "$VERBOSE_MODE" = "true" ]; then
    echo "DKIM configuration completed."
fi 