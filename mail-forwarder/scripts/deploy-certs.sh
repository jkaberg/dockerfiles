#!/bin/bash
set -e

# This script is called by certbot after new certificates are obtained
# It updates Postfix configuration and restarts the service

# Get the primary domain from environment
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
PRIMARY_DOMAIN=${DOMAIN_ARRAY[0]}

# Check if we have valid certificates
if [ -f "/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem" ]; then
    echo "Deploying new certificates for $PRIMARY_DOMAIN..."
    
    # Update Postfix configuration
    postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem"
    postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem"
    
    # Reload Postfix to apply changes
    service postfix reload
    
    echo "Certificate deployment completed."
else
    echo "No certificates found for $PRIMARY_DOMAIN!"
    exit 1
fi 