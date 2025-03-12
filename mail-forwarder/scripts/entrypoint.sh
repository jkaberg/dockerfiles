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
: "${VERBOSE_DNS_CHECK:=false}"  # New parameter to control DNS check verbosity
: "${SILENT_MODE:=false}"        # New parameter for global silent mode
: "${MAIL_HOSTNAME:=mail.example.com}"
: "${ACME_METHOD:=tls-alpn}"  # Default to TLS-ALPN, fallback to HTTP
: "${ALPN_PORT:=587}"         # Default port for TLS-ALPN verification
: "${RENEWAL_DAYS:=7}"        # Only renew if certificate expires within this many days

# If SILENT_MODE is enabled, set DNS_CHECK to non-verbose
if [ "$SILENT_MODE" = "true" ]; then
    VERBOSE_DNS_CHECK="false"
fi

# Extract domains from MAIL_FORWARDS if set, or use default
if [ -n "$MAIL_FORWARDS" ]; then
    # Extract all domains from the forwarding rules
    EXTRACTED_DOMAINS=""
    IFS=';' read -ra FORWARDS <<< "$MAIL_FORWARDS"
    for forward in "${FORWARDS[@]}"; do
        if [[ "$forward" == *":"* ]]; then
            SOURCE=$(echo "$forward" | cut -d: -f1)
            # Handle both *@domain.com and user@domain.com formats
            if [[ "$SOURCE" == *"@"* ]]; then
                # Extract domain part after @
                DOMAIN=$(echo "$SOURCE" | cut -d@ -f2)
                # Add to our list if not already there
                if [[ -n "$DOMAIN" && "$EXTRACTED_DOMAINS" != *"$DOMAIN"* ]]; then
                    [ -n "$EXTRACTED_DOMAINS" ] && EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS,"
                    EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS$DOMAIN"
                fi
            elif [[ "$SOURCE" == *"."* ]]; then
                # Handle domain.com format (catch-all without @)
                DOMAIN="$SOURCE"
                if [[ -n "$DOMAIN" && "$EXTRACTED_DOMAINS" != *"$DOMAIN"* ]]; then
                    [ -n "$EXTRACTED_DOMAINS" ] && EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS,"
                    EXTRACTED_DOMAINS="$EXTRACTED_DOMAINS$DOMAIN"
                fi
            fi
        fi
    done
    
    # Use extracted domains if any were found
    if [ -n "$EXTRACTED_DOMAINS" ]; then
        MAIL_DOMAINS="$EXTRACTED_DOMAINS"
        echo "Extracted mail domains from forwarding rules: $MAIL_DOMAINS"
    else
        # Fallback to default
        MAIL_DOMAINS="example.com"
        echo "Warning: Could not extract domains from MAIL_FORWARDS, using default: $MAIL_DOMAINS"
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

# Configure supervisor
cp /opt/config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Function to display TLS certificate information
display_tls_status() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                       TLS CERTIFICATE STATUS                             "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    printf "%-20s %-30s %-25s\n" "DOMAIN" "EXPIRY" "STATUS"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    # Check status for each domain
    local cert_found=false
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
            cert_found=true
            # Get expiry date
            expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" | cut -d= -f2-)
            expiry_seconds=$(date -d "$expiry" +%s)
            now_seconds=$(date +%s)
            days_left=$(( (expiry_seconds - now_seconds) / 86400 ))
            
            # Format status based on expiry
            if [ $days_left -gt 30 ]; then
                status_colored="\e[32m✅ Valid ($days_left days)\e[0m"
            elif [ $days_left -gt 7 ]; then
                status_colored="\e[33m⚠️ Renewal soon\e[0m"
            else
                status_colored="\e[31m⚠️ Expiring soon!\e[0m"
            fi
            
            printf "%-20s %-30s %-25b\n" "$domain" "$expiry" "$status_colored"
        fi
    done
    
    # If no certs found, show self-signed status
    if [ "$cert_found" != "true" ]; then
        printf "%-20s %-30s %-25b\n" "$PRIMARY_DOMAIN" "1 year from startup" "\e[33m⚠️ Self-signed\e[0m"
    fi
    
    echo "───────────────────────────────────────────────────────────────────────────"
    printf "%-20s %-30s %-25s\n" "Renewal method:" "$ACME_METHOD" "Every $RENEWAL_DAYS days"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to display server configuration info
display_server_config() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                 MAIL FORWARDER AND SMTP RELAY SERVER                     "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    printf "%-22s %-52s\n" "SETTING" "VALUE"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    printf "%-22s %-52s\n" "Mail domains:" "$MAIL_DOMAINS"
    printf "%-22s %-52s\n" "Mail hostname:" "$MAIL_HOSTNAME"
    printf "%-22s %-52s\n" "DKIM enabled:" "$ENABLE_DKIM"
    printf "%-22s %-52s\n" "TLS enabled:" "$ENABLE_TLS"
    printf "%-22s %-52s\n" "SMTP authentication:" "$ENABLE_SMTP_AUTH"
    
    # Add more details if relaying is configured
    if [ -n "$SMTP_RELAY_HOST" ]; then
        echo "───────────────────────────────────────────────────────────────────────────"
        printf "%-22s %-52s\n" "SMTP relay:" "$SMTP_RELAY_HOST:$SMTP_RELAY_PORT"
        
        if [ -n "$SMTP_RELAY_USERNAME" ]; then
            printf "%-22s %-52s\n" "Relay authentication:" "Enabled"
        else
            printf "%-22s %-52s\n" "Relay authentication:" "Disabled"
        fi
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

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
        echo "TLS certificates found, renewing if needed..."
        
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
if [ "$SILENT_MODE" != "true" ]; then
    echo ""
    # Display server configuration 
    display_server_config
    
    # Display TLS certificate status
    display_tls_status
fi

# Verify DNS configuration if enabled
if [ "$VERIFY_DNS" = "true" ]; then
    # Wait a moment for services to initialize
    sleep 2
    
    # Export DNS verbosity setting so the verification script can use it
    export VERBOSE_DNS_CHECK
    
    /opt/scripts/verify-dns.sh
fi

# Execute CMD
exec "$@" 