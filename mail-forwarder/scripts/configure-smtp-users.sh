#!/bin/bash
set -e

# Install necessary packages for SASL authentication
apt-get update && apt-get install -y --no-install-recommends libsasl2-modules && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure SASL authentication
mkdir -p /etc/sasl2/
cat > /etc/sasl2/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF

# Parse SMTP users in format user1:password;user2:password
if [ -n "$SMTP_USERS" ]; then
    echo "Setting up SMTP authentication users..."
    
    # Create or reset sasldb2
    [ -f /etc/sasl2/sasldb2 ] && rm -f /etc/sasl2/sasldb2
    
    IFS=';' read -ra USERS <<< "$SMTP_USERS"
    for user_config in "${USERS[@]}"; do
        if [[ "$user_config" == *":"* ]]; then
            USERNAME=$(echo "$user_config" | cut -d: -f1)
            PASSWORD=$(echo "$user_config" | cut -d: -f2)
            
            # Get primary domain for the SASL realm
            IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
            PRIMARY_DOMAIN=${DOMAIN_ARRAY[0]}
            
            # Create the user
            echo "$PASSWORD" | saslpasswd2 -p -c -u "$PRIMARY_DOMAIN" "$USERNAME"
            echo "Created SMTP user: $USERNAME@$PRIMARY_DOMAIN"
        fi
    done
    
    # Set permissions
    chown postfix:sasl /etc/sasl2/sasldb2
    chmod 640 /etc/sasl2/sasldb2
    
    # List users for verification
    sasldblistusers2
    
    # Make sure SASL auth is enabled
    postconf "smtpd_sasl_auth_enable = yes"
else
    echo "No SMTP users configured."
    
    # Disable SASL auth if no users
    if [ "$ENABLE_SMTP_AUTH" != "true" ]; then
        postconf "smtpd_sasl_auth_enable = no"
    fi
fi 