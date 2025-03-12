#!/bin/bash
set -e

# Create an array of domains
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"

# Display forwarding configuration in a table
display_forward_config() {
    if [ ${#FORWARD_CONFIG[@]} -eq 0 ] && [ ${#CATCH_ALL_CONFIG[@]} -eq 0 ]; then
        return
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                     MAIL FORWARDING CONFIGURATION                      "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ${#FORWARD_CONFIG[@]} -gt 0 ]; then
        printf "%-25s %-35s %-15s\n" "SOURCE ADDRESS" "DESTINATION" "TYPE"
        echo "───────────────────────────────────────────────────────────────────────────"
        
        for forward in "${FORWARD_CONFIG[@]}"; do
            source=$(echo "$forward" | cut -d: -f1)
            destination=$(echo "$forward" | cut -d: -f2)
            printf "%-25s %-35s %-15s\n" "$source" "$destination" "Forward"
        done
    fi
    
    if [ ${#CATCH_ALL_CONFIG[@]} -gt 0 ]; then
        # Add a separator if we displayed forwards
        if [ ${#FORWARD_CONFIG[@]} -gt 0 ]; then
            echo "───────────────────────────────────────────────────────────────────────────"
        else
            printf "%-25s %-35s %-15s\n" "DOMAIN" "DESTINATION" "TYPE"
            echo "───────────────────────────────────────────────────────────────────────────"
        fi
        
        for catch_all in "${CATCH_ALL_CONFIG[@]}"; do
            domain=$(echo "$catch_all" | cut -d: -f1)
            destination=$(echo "$catch_all" | cut -d: -f2)
            printf "%-25s %-35s %-15s\n" "$domain" "$destination" "Catch-All"
        done
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to set up mail forwarding
setup_forwarding() {
    echo "Setting up mail forwarding..."
    
    # Arrays to store configuration for display
    FORWARD_CONFIG=()
    CATCH_ALL_CONFIG=()
    
    # Create relay_domains file if it doesn't exist
    touch /etc/postfix/relay_domains
    
    # Create virtual file or empty it if it exists
    > /etc/postfix/virtual
    
    if [ -n "$MAIL_FORWARDS" ]; then
        # Remove any quotes from the MAIL_FORWARDS variable
        MAIL_FORWARDS_CLEAN=$(echo "$MAIL_FORWARDS" | tr -d '"')
        
        IFS=';' read -ra FORWARDS <<< "$MAIL_FORWARDS_CLEAN"
        for forward in "${FORWARDS[@]}"; do
            if [[ "$forward" == *":"* ]]; then
                # Split the forwarding rule
                source=$(echo "$forward" | cut -d: -f1)
                destinations=$(echo "$forward" | cut -d: -f2-)
                
                # Remove any quotes or extra spaces
                source=$(echo "$source" | tr -d '"' | xargs)
                destinations=$(echo "$destinations" | tr -d '"' | xargs)
                
                # Store for display later
                FORWARD_CONFIG+=("$source:$destinations")
                
                if [[ "$source" == *"@"* ]]; then
                    # It's a regular forward
                    domain=$(echo "$source" | cut -d@ -f2)
                    user=$(echo "$source" | cut -d@ -f1)
                    
                    # Create virtual directory structure if it doesn't exist
                    mkdir -p "/var/mail/vhosts/$domain"
                    
                    # Add to the virtual file - make sure we don't add quotes around the pattern
                    echo "$source $destinations" >> /etc/postfix/virtual
                    echo "Created forward from $source to $destinations"
                    
                    # Add domain to the relay domains if not already there
                    if ! grep -q "^$domain$" /etc/postfix/relay_domains 2>/dev/null; then
                        echo "$domain" >> /etc/postfix/relay_domains
                    fi
                elif [[ "$source" == *"."* ]]; then
                    # It's a domain-wide catch-all
                    # Store for display
                    CATCH_ALL_CONFIG+=("$source:$destinations")
                    
                    # Add the catch-all to virtual
                    echo "@$source $destinations" >> /etc/postfix/virtual
                    echo "Created catch-all forward for $source to $destinations"
                    
                    # Add domain to the relay domains
                    if ! grep -q "^$source$" /etc/postfix/relay_domains 2>/dev/null; then
                        echo "$source" >> /etc/postfix/relay_domains
                    fi
                fi
            fi
        done
    fi
    
    # Build lookup tables
    postmap /etc/postfix/virtual
    
    # Display the configuration in a table
    display_forward_config
}

# Parse mail forwards in format user1@domain1.com:external1@example.com;*@domain2.com:external2@example.com
if [ -n "$MAIL_FORWARDS" ]; then
    setup_forwarding
else
    echo "No mail forwards configured."

    # Still ensure we have at least one virtual mailbox per domain
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "postmaster@$domain /dev/null" >> /etc/postfix/virtual_mailboxes
    done
    postmap /etc/postfix/virtual_mailboxes
fi 