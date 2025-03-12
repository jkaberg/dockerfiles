#!/bin/bash
set -e

# Default configuration
: "${SMTP_PORT:=25}"
: "${SUBMISSION_PORT:=587}"
: "${SMTPS_PORT:=465}"
: "${SMTP_RELAY_HOST:=}"
: "${SMTP_RELAY_PORT:=25}"
: "${SMTP_RELAY_USERNAME:=}"
: "${SMTP_RELAY_PASSWORD:=}"
: "${MAIL_FORWARDS:=}"
: "${SMTP_USERS:=}"
: "${ENABLE_DKIM:=true}"
: "${ENABLE_TLS:=true}"
: "${ENABLE_SMTP_AUTH:=true}"
: "${VERIFY_DNS:=true}"
: "${MAIL_HOSTNAME:=mail.example.com}"
: "${ACME_METHOD:=tls-alpn}"  # Default to TLS-ALPN, fallback to HTTP
: "${ALPN_PORT:=587}"         # Default port for TLS-ALPN verification
: "${RENEWAL_DAYS:=7}"        # Only renew if certificate expires within this many days

# Extract domains from MAIL_FORWARDS if set, or use default
if [ -n "$MAIL_FORWARDS" ]; then
    # Extract all domains from the forwarding rules
    EXTRACTED_DOMAINS=""
    IFS=';' read -ra FORWARDS <<< "$MAIL_FORWARDS"
    for forward in "${FORWARDS[@]}"; do
        if [[ "$forward" == *":"* ]]; then
            SOURCE=$(echo "$forward" | cut -d: -f1)
            if [[ "$SOURCE" == *"@"* ]]; then
                DOMAIN=$(echo "$SOURCE" | cut -d@ -f2)
                # Add to our list if not already there
                if [[ "$EXTRACTED_DOMAINS" != *"$DOMAIN"* ]]; then
                    [ -n "$EXTRACTED_DOMAINS" ] && EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS,"
                    EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS$DOMAIN"
                fi
            fi
        fi
    done
    
    # Use extracted domains if any were found
    if [ -n "$EXTRACTED_DOMAINS" ]; then
        MAIL_DOMAINS="$EXTRACTED_DOMAINS"
    else
        # Fallback to default
        MAIL_DOMAINS="example.com"
    fi
else
    # No forwards defined, use default domain
    : "${MAIL_DOMAINS:=example.com}"
fi

# For backward compatibility, also set MAIL_DOMAINS from MAIL_DOMAIN if it exists
if [ -z "$MAIL_DOMAINS" ] && [ -n "$MAIL_DOMAIN" ]; then
    MAIL_DOMAINS="$MAIL_DOMAIN"
fi

# Set default ACME email based on primary domain
: "${ACME_EMAIL:=admin@$(echo "$MAIL_DOMAINS" | cut -d, -f1)}"
: "${TLS_CERT_DOMAIN:=$MAIL_HOSTNAME}"
: "${SMTP_NETWORKS:=127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16}"

# Create an array of domains
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
PRIMARY_DOMAIN=${DOMAIN_ARRAY[0]}

# Configure rsyslog
cp /opt/config/rsyslog.conf /etc/rsyslog.conf
service rsyslog start

# Configure supervisor
cp /opt/config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configure certificates
if [ "$ENABLE_TLS" = "true" ]; then
    # Check if we have certificates
    CERT_EXISTS=false
    for domain in "${DOMAIN_ARRAY[@]}"; do
        if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
            CERT_EXISTS=true
            break
        fi
    done

    if [ "$CERT_EXISTS" = "false" ]; then
        echo "No TLS certificates found, generating self-signed certificate for now..."
        mkdir -p /etc/letsencrypt/live/$PRIMARY_DOMAIN
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem \
          -out /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem \
          -subj "/CN=$PRIMARY_DOMAIN"
        
        # Schedule certificate renewal
        echo "Setting up Let's Encrypt certificate retrieval..."
        
        # Build domain arguments
        DOMAIN_ARGS=""
        for domain in "${DOMAIN_ARRAY[@]}"; do
            DOMAIN_ARGS="$DOMAIN_ARGS -d $domain"
        done
        
        # Set up certificate renewal based on verification method
        if [ "$ACME_METHOD" = "tls-alpn" ]; then
            echo "Using TLS-ALPN challenge method on port $ALPN_PORT"
            
            # Check if certbot-nginx package is installed (required for tls-alpn)
            if ! dpkg -l | grep -q certbot-nginx; then
                echo "Installing certbot-nginx for TLS-ALPN support..."
                apt-get update && apt-get install -y python3-certbot-nginx
            fi
            
            # Create a temporary pause script for Postfix during verification
            cat <<EOF > /opt/scripts/pause-postfix.sh
#!/bin/bash
# This script temporarily stops postfix to allow certbot to bind to the SMTP ports
service postfix stop
EOF

            # Create a resume script for Postfix after verification
            cat <<EOF > /opt/scripts/resume-postfix.sh
#!/bin/bash
# This script restarts postfix after certbot has completed TLS-ALPN verification
service postfix start
EOF

            chmod +x /opt/scripts/pause-postfix.sh /opt/scripts/resume-postfix.sh
            
            # Initial certificate request
            echo "Performing initial certificate request..."
            /opt/scripts/pause-postfix.sh
            certbot certonly --authenticator tls-alpn-01 --tls-alpn-01-port $ALPN_PORT \
                --deploy-hook "/opt/scripts/deploy-certs.sh" \
                --post-hook "/opt/scripts/resume-postfix.sh" \
                --non-interactive --agree-tos -m $ACME_EMAIL $DOMAIN_ARGS || true
            /opt/scripts/resume-postfix.sh
            
            # Create renewal configuration for TLS-ALPN challenge
            cat <<EOF > /etc/letsencrypt/renewal-hooks/pre/pause-postfix.sh
#!/bin/bash
# This script temporarily stops postfix before renewal attempts
service postfix stop
EOF

            cat <<EOF > /etc/letsencrypt/renewal-hooks/post/resume-postfix.sh
#!/bin/bash
# This script restarts postfix after renewal attempts
service postfix start
# Deploy certificates if renewed
/opt/scripts/deploy-certs.sh
EOF

            chmod +x /etc/letsencrypt/renewal-hooks/pre/pause-postfix.sh
            chmod +x /etc/letsencrypt/renewal-hooks/post/resume-postfix.sh
            
            # Create a cron job that only renews certificates when needed
            cat <<EOF > /etc/cron.d/certbot-renew
0 0,12 * * * root certbot renew --cert-name $PRIMARY_DOMAIN --days-before-expiry $RENEWAL_DAYS --quiet
EOF
        else
            # Fallback to HTTP-01 challenge
            echo "Using HTTP-01 challenge method"
            
            # Initial certificate request
            echo "Performing initial certificate request..."
            certbot certonly --standalone --preferred-challenges http --http-01-port 80 \
                --deploy-hook "/opt/scripts/deploy-certs.sh" \
                --non-interactive --agree-tos -m $ACME_EMAIL $DOMAIN_ARGS || true
            
            # Create renewal hook for HTTP-01 challenge
            mkdir -p /etc/letsencrypt/renewal-hooks/deploy
            ln -sf /opt/scripts/deploy-certs.sh /etc/letsencrypt/renewal-hooks/deploy/deploy-certs.sh
            
            # Create a cron job that only renews certificates when needed
            cat <<EOF > /etc/cron.d/certbot-renew
0 0,12 * * * root certbot renew --cert-name $PRIMARY_DOMAIN --days-before-expiry $RENEWAL_DAYS --quiet
EOF
        fi
    else
        # Certificates exist, just set up renewal
        echo "TLS certificates found, setting up renewal checks..."
        
        if [ "$ACME_METHOD" = "tls-alpn" ]; then
            # Ensure renewal hooks are set up for TLS-ALPN
            mkdir -p /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post
            
            cat <<EOF > /etc/letsencrypt/renewal-hooks/pre/pause-postfix.sh
#!/bin/bash
# This script temporarily stops postfix before renewal attempts
service postfix stop
EOF

            cat <<EOF > /etc/letsencrypt/renewal-hooks/post/resume-postfix.sh
#!/bin/bash
# This script restarts postfix after renewal attempts
service postfix start
# Deploy certificates if renewed
/opt/scripts/deploy-certs.sh
EOF

            chmod +x /etc/letsencrypt/renewal-hooks/pre/pause-postfix.sh
            chmod +x /etc/letsencrypt/renewal-hooks/post/resume-postfix.sh
        else
            # Ensure renewal hooks are set up for HTTP-01
            mkdir -p /etc/letsencrypt/renewal-hooks/deploy
            ln -sf /opt/scripts/deploy-certs.sh /etc/letsencrypt/renewal-hooks/deploy/deploy-certs.sh
        fi
        
        # Create a cron job that only renews certificates when needed (for both methods)
        cat <<EOF > /etc/cron.d/certbot-renew
0 0,12 * * * root certbot renew --days-before-expiry $RENEWAL_DAYS --quiet
EOF
    fi
fi

# Configure Postfix
/opt/scripts/configure-postfix.sh

# Set up mail forwarding
/opt/scripts/configure-forwarding.sh

# Set up SMTP users
/opt/scripts/configure-smtp-users.sh

# Set up DKIM if enabled
if [ "$ENABLE_DKIM" = "true" ]; then
    /opt/scripts/configure-dkim.sh
fi

# Print startup banner
echo ""
echo "================================================================="
echo "          MAIL FORWARDER AND SMTP RELAY SERVER                   "
echo "================================================================="
echo "Server configured with the following settings:"
echo "Mail domains: $MAIL_DOMAINS"
echo "Mail hostname: $MAIL_HOSTNAME"
echo "DKIM enabled: $ENABLE_DKIM"
echo "TLS enabled: $ENABLE_TLS"
if [ "$ENABLE_TLS" = "true" ]; then
    echo "ACME verification: $ACME_METHOD"
    if [ "$ACME_METHOD" = "tls-alpn" ]; then
        echo "TLS-ALPN port: $ALPN_PORT"
    fi
    echo "Certificate renewal: Within $RENEWAL_DAYS days of expiration"
fi
echo "SMTP Authentication enabled: $ENABLE_SMTP_AUTH"
echo "================================================================="
echo ""

# Verify DNS configuration if enabled
if [ "$VERIFY_DNS" = "true" ]; then
    # Wait a moment for services to initialize
    sleep 2
    /opt/scripts/verify-dns.sh
fi

# Execute CMD
exec "$@" 