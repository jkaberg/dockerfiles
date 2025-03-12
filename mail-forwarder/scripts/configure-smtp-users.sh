#!/bin/bash
set -e

# Configure SASL authentication
mkdir -p /etc/sasl2/
cat > /etc/sasl2/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
log_level: 7
EOF

# Also create the same config in Postfix chroot
mkdir -p /var/spool/postfix/etc/sasl2/
cp /etc/sasl2/smtpd.conf /var/spool/postfix/etc/sasl2/

# Ensure Postfix has proper SASL configuration
postconf -e "smtpd_sasl_type = cyrus"
postconf -e "smtpd_sasl_path = smtpd"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "broken_sasl_auth_clients = yes"

# Display SMTP users configuration in a table
display_smtp_users_config() {
    if [ ${#SMTP_USER_CONFIG[@]} -eq 0 ]; then
        return
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                     SMTP AUTHENTICATION USERS                           "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    printf "%-25s %-20s %-25s\n" "USERNAME" "STATUS" "DOMAINS"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    for config in "${SMTP_USER_CONFIG[@]}"; do
        username=$(echo "$config" | cut -d: -f1)
        status=$(echo "$config" | cut -d: -f2)
        domains=$(echo "$config" | cut -d: -f3)
        
        # Set color based on status
        if [[ "$status" == "Created" ]]; then
            status_colored="\e[32m✅ Created\e[0m"
        elif [[ "$status" == "Updated" ]]; then
            status_colored="\e[33m🔄 Updated\e[0m"
        else
            status_colored="\e[31m❌ Failed\e[0m"
        fi
        
        printf "%-25s %-20b %-25s\n" "$username" "$status_colored" "$domains"
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to set up SMTP users
setup_smtp_users() {
    echo "Setting up SMTP authentication users..."
    
    # Arrays to store configuration for display
    SMTP_USER_CONFIG=()
    
    if [ -n "$SMTP_USERS" ]; then
        IFS=';' read -ra USERS <<< "$SMTP_USERS"
        for user_entry in "${USERS[@]}"; do
            if [[ "$user_entry" == *":"* ]]; then
                # Split the user entry
                username=$(echo "$user_entry" | cut -d: -f1)
                password=$(echo "$user_entry" | cut -d: -f2)
                
                # Extract domain if present
                if [[ "$username" == *"@"* ]]; then
                    domain=$(echo "$username" | cut -d@ -f2)
                else
                    domain="(all domains)"
                fi
                
                # Create the user
                echo "$password" | saslpasswd2 -p -c -u "$HOSTNAME" "$username"
                if [ $? -eq 0 ]; then
                    echo "Created SMTP user: $username"
                    SMTP_USER_CONFIG+=("$username:Created:$domain")
                else
                    echo "Failed to create SMTP user: $username"
                    SMTP_USER_CONFIG+=("$username:Failed:$domain")
                fi
            fi
        done
        
        # Verify SASL database
        if [[ $(sasldblistusers2 | wc -l) -eq 0 ]]; then
            echo -e "\e[33mWarning: SASL database appears to be empty or was not created properly.\e[0m"
            echo "/etc/sasl2/sasldb2"
            echo "/etc/sasldb2"
            sasldblistusers2
        fi
    else
        echo "No SMTP users configured."
    fi
    
    # Display the configuration in a table
    display_smtp_users_config
}

# Set up SASL authentication
if [ "$ENABLE_SMTP_AUTH" = "true" ]; then
    setup_smtp_users
else
    echo "SMTP authentication disabled. Not configuring any SMTP users."
fi 