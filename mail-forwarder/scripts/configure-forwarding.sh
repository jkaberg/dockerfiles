#!/bin/bash
set -e

# Create an array of domains
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"

# Parse mail forwards in format user1@domain1.com:external1@example.com;*@domain2.com:external2@example.com
if [ -n "$MAIL_FORWARDS" ]; then
    echo "Setting up mail forwarding..."
    rm -f /etc/postfix/virtual_aliases
    touch /etc/postfix/virtual_aliases

    IFS=';' read -ra FORWARDS <<< "$MAIL_FORWARDS"
    for forward in "${FORWARDS[@]}"; do
        if [[ "$forward" == *":"* ]]; then
            SOURCE=$(echo "$forward" | cut -d: -f1)
            DESTINATION=$(echo "$forward" | cut -d: -f2)
            
            # Check if this is a wildcard forward
            if [[ "$SOURCE" == *"*@"* ]]; then
                # Extract domain from wildcard
                DOMAIN=$(echo "$SOURCE" | cut -d@ -f2)
                PATTERN=$(echo "$SOURCE" | cut -d@ -f1)
                
                # Create a catch-all using regexp
                if [ "$PATTERN" = "*" ]; then
                    echo "/@$DOMAIN/ $DESTINATION" >> /etc/postfix/virtual_aliases
                    echo "Created catch-all forward for $DOMAIN to $DESTINATION"
                else
                    # Handle partial wildcards (e.g., prefix* or *suffix)
                    REGEXP=$(echo "$PATTERN" | sed 's/\*/.*/g')
                    echo "/^$REGEXP@$DOMAIN/ $DESTINATION" >> /etc/postfix/virtual_aliases
                    echo "Created pattern forward for $REGEXP@$DOMAIN to $DESTINATION"
                fi
            else
                # Regular forward
                echo "$SOURCE $DESTINATION" >> /etc/postfix/virtual_aliases
                echo "Created forward from $SOURCE to $DESTINATION"
            fi
        fi
    done

    # For each domain, ensure we have at least one virtual mailbox
    for domain in "${DOMAIN_ARRAY[@]}"; do
        # If no explicit mailbox for this domain, create a dummy
        grep -q "@$domain" /etc/postfix/virtual_mailboxes || echo "postmaster@$domain /dev/null" >> /etc/postfix/virtual_mailboxes
    done

    # Update Postfix with the new configuration
    postmap /etc/postfix/virtual_aliases
    postmap /etc/postfix/virtual_mailboxes
else
    echo "No mail forwards configured."

    # Still ensure we have at least one virtual mailbox per domain
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "postmaster@$domain /dev/null" >> /etc/postfix/virtual_mailboxes
    done
    postmap /etc/postfix/virtual_mailboxes
fi 