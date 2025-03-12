#!/bin/bash
set -e

# Source our table formatter utility
if [ -f "$(dirname "$0")/table-formatter.sh" ]; then
    source "$(dirname "$0")/table-formatter.sh"
else
    echo "Error: table-formatter.sh not found. Please ensure it's in the same directory as this script."
    exit 1
fi

# Source environment variables
if [ -f "/etc/environment" ]; then
    source /etc/environment
fi

# Make sure environment variables are set with defaults if missing
: "${MAIL_DOMAINS:=example.com}"
: "${MAIL_HOSTNAME:=mail.example.com}"
: "${ENABLE_DKIM:=true}"
: "${ENABLE_SPAMASSASSIN:=true}"
: "${ENABLE_FAIL2BAN:=true}"
: "${ENABLE_CLAMAV:=false}"

# Function to get the public IP address
get_public_ip() {
    PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
    echo "$PUBLIC_IP"
}

# Function to display system configuration
display_system_config() {
    local title="MAIL FORWARDER SYSTEM CONFIGURATION"
    local headers="SETTING,VALUE,STATUS"
    local rows=()

    # Get system information
    local hostname=$(hostname -f)
    local ip_address=$(get_public_ip)
    local postfix_version=$(postconf -d mail_version 2>/dev/null | awk '{print $3}' || echo "Unknown")
    local dovecot_version=$(dovecot --version 2>/dev/null || echo "Unknown")
    local opendkim_version=$(opendkim -V 2>/dev/null | head -1 | awk '{print $3}' || echo "Unknown")
    
    # Add rows for system config
    rows+=("Hostname,$hostname,✅ Active")
    rows+=("Public IP,$ip_address,✅ Active")
    rows+=("Mail Domains,$MAIL_DOMAINS,✅ Configured")
    rows+=("Mail Hostname,$MAIL_HOSTNAME,✅ Configured")
    
    # Add rows for service versions
    rows+=("Postfix Version,$postfix_version,✅ Installed")
    rows+=("Dovecot Version,$dovecot_version,✅ Installed")
    rows+=("OpenDKIM Version,$opendkim_version,✅ Installed")
    
    # Add rows for enabled features
    if [ "$ENABLE_DKIM" = "true" ]; then
        rows+=("DKIM,Enabled,✅ Active")
    else
        rows+=("DKIM,Disabled,⚠️ Inactive")
    fi
    
    if [ "$ENABLE_SPAMASSASSIN" = "true" ]; then
        rows+=("SpamAssassin,Enabled,✅ Active")
    else
        rows+=("SpamAssassin,Disabled,⚠️ Inactive")
    fi
    
    if [ "$ENABLE_FAIL2BAN" = "true" ]; then
        rows+=("Fail2Ban,Enabled,✅ Active")
    else
        rows+=("Fail2Ban,Disabled,⚠️ Inactive")
    fi
    
    if [ "$ENABLE_CLAMAV" = "true" ]; then
        rows+=("ClamAV,Enabled,✅ Active")
    else
        rows+=("ClamAV,Disabled,ℹ️ Inactive")
    fi
    
    # Create the table
    create_table "$title" "$headers" "${rows[@]}"
}

# Function to display email forwarding configuration
display_forwarding_config() {
    if [ -f "/etc/postfix/virtual" ]; then
        create_forwarding_table "/etc/postfix/virtual"
    else
        echo "No email forwarding configuration found."
    fi
}

# Function to display service status
display_service_status() {
    local title="MAIL SERVICES STATUS"
    local headers="SERVICE,STATUS,DETAILS"
    local rows=()
    
    # Check Postfix
    if service postfix status >/dev/null 2>&1; then
        rows+=("Postfix,✅ Running,Mail Transfer Agent")
    else
        rows+=("Postfix,❌ Stopped,Mail Transfer Agent")
    fi
    
    # Check Dovecot
    if service dovecot status >/dev/null 2>&1; then
        rows+=("Dovecot,✅ Running,IMAP/POP3 Server")
    else
        rows+=("Dovecot,❌ Stopped,IMAP/POP3 Server")
    fi
    
    # Check OpenDKIM if enabled
    if [ "$ENABLE_DKIM" = "true" ]; then
        if service opendkim status >/dev/null 2>&1; then
            rows+=("OpenDKIM,✅ Running,DKIM Signing Service")
        else
            rows+=("OpenDKIM,❌ Stopped,DKIM Signing Service")
        fi
    fi
    
    # Check SpamAssassin if enabled
    if [ "$ENABLE_SPAMASSASSIN" = "true" ]; then
        if service spamassassin status >/dev/null 2>&1; then
            rows+=("SpamAssassin,✅ Running,Spam Filter")
        else
            rows+=("SpamAssassin,❌ Stopped,Spam Filter")
        fi
    fi
    
    # Check Fail2Ban if enabled
    if [ "$ENABLE_FAIL2BAN" = "true" ]; then
        if service fail2ban status >/dev/null 2>&1; then
            rows+=("Fail2Ban,✅ Running,Intrusion Prevention")
        else
            rows+=("Fail2Ban,❌ Stopped,Intrusion Prevention")
        fi
    fi
    
    # Check ClamAV if enabled
    if [ "$ENABLE_CLAMAV" = "true" ]; then
        if service clamav-daemon status >/dev/null 2>&1; then
            rows+=("ClamAV,✅ Running,Antivirus")
        else
            rows+=("ClamAV,❌ Stopped,Antivirus")
        fi
    fi
    
    # Create the table
    create_table "$title" "$headers" "${rows[@]}"
}

# Main function to display all configurations
show_mail_config() {
    echo "======================= MAIL FORWARDER CONFIGURATION ======================="
    echo "Checking system configuration and services..."
    
    # Display system configuration
    display_system_config
    echo ""
    
    # Display service status
    display_service_status
    echo ""
    
    # Display forwarding configuration
    display_forwarding_config
    echo ""
    
    # Display DNS configuration using function from table-formatter.sh
    echo "Checking DNS configurations..."
    create_dns_table "$MAIL_DOMAINS"
    echo ""
    
    # If DKIM is enabled, show DKIM specific configuration
    if [ "$ENABLE_DKIM" = "true" ]; then
        create_dkim_table "$MAIL_DOMAINS"
        echo ""
    fi
    
    echo "======================= CONFIGURATION SUMMARY ======================="
    if [ -f "/opt/dns_requirements.txt" ]; then
        echo "📝 Detailed DNS requirements are available in: /opt/dns_requirements.txt"
    fi
    
    echo "✉️  Your mail forwarder is configured to handle mail for: $MAIL_DOMAINS"
    
    # Check if we have any forwarding rules
    if [ -f "/etc/postfix/virtual" ]; then
        local forwarding_count=$(grep -v '^$\|^#' "/etc/postfix/virtual" | wc -l)
        echo "📨 Currently forwarding $forwarding_count email address(es)"
    else
        echo "⚠️  No email forwarding rules have been configured yet"
    fi
    
    echo "=====================================================================\n"
}

# Run the main function
show_mail_config 