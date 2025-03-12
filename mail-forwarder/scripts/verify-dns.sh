#!/bin/bash
set -e

# Function to check if dig command is available, if not install it
ensure_dig_installed() {
    if ! command -v dig &> /dev/null; then
        echo "Installing dig (dnsutils)..."
        apt-get update && apt-get install -y dnsutils && apt-get clean && rm -rf /var/lib/apt/lists/*
    fi
}

# Function to get the public IP address
get_public_ip() {
    # Try multiple services to get our public IP
    for ip_service in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        public_ip=$(wget -qO- $ip_service 2>/dev/null || curl -s $ip_service 2>/dev/null)
        if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$public_ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# Function to check PTR record
check_ptr_record() {
    local hostname="$1"
    
    echo -n "Checking PTR record... "
    
    # Get our public IP
    local public_ip=$(get_public_ip)
    
    if [ -z "$public_ip" ]; then
        echo -e "\e[33mSKIPPED: Could not determine public IP address\e[0m"
        echo "Please check manually that your server's IP address has a valid PTR record."
        return 0
    fi
    
    # Convert IP to reverse DNS format for lookup
    local reversed_ip=$(echo "$public_ip" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa"}')
    
    # Get the PTR record
    local ptr_record=$(dig +short -x "$public_ip")
    
    if [ -z "$ptr_record" ]; then
        echo -e "\e[31mFAIL: No PTR record found for $public_ip\e[0m"
        echo "Recommended action: Set up a PTR record for $public_ip pointing to $hostname"
        return 1
    fi
    
    # Remove trailing dot if present
    ptr_record="${ptr_record%.}"
    
    # Check if the PTR record matches or contains our hostname
    if [[ "$ptr_record" == "$hostname" || "$ptr_record" == *"$hostname"* || "$hostname" == *"$ptr_record"* ]]; then
        echo -e "\e[32mOK\e[0m"
        echo "IP: $public_ip → PTR: $ptr_record"
        return 0
    else
        echo -e "\e[33mWARNING: PTR record exists but doesn't match hostname\e[0m"
        echo "IP: $public_ip → Current PTR: $ptr_record"
        echo "Recommended: PTR should point to $hostname"
        return 1
    fi
}

# Function to check MX records
check_mx_records() {
    local domain="$1"
    local hostname="$2"
    
    echo -n "Checking MX records for $domain... "
    
    # Get MX records
    mx_records=$(dig +short MX "$domain" | sort -n)
    
    if [ -z "$mx_records" ]; then
        echo -e "\e[31mFAIL: No MX records found\e[0m"
        return 1
    fi
    
    # Check if any MX record points to the mail hostname
    if echo "$mx_records" | grep -q "$hostname"; then
        echo -e "\e[32mOK\e[0m"
        return 0
    else
        echo -e "\e[33mWARNING: MX records exist but none point to $hostname\e[0m"
        echo "Found MX records:"
        echo "$mx_records"
        return 1
    fi
}

# Function to check DKIM records
check_dkim_records() {
    local domain="$1"
    
    if [ "$ENABLE_DKIM" != "true" ]; then
        echo "DKIM disabled, skipping DKIM DNS check for $domain"
        return 0
    fi
    
    echo -n "Checking DKIM records for $domain... "
    
    # Check if DKIM key exists locally first
    if [ ! -f "/var/mail/dkim/$domain/mail.txt" ]; then
        echo -e "\e[33mWARNING: DKIM is enabled but no key found locally for $domain\e[0m"
        return 1
    fi
    
    # Get the expected DKIM value (without quotation marks and header)
    expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'p=.*"' | tr -d '"')
    
    # Get the actual DKIM record
    dkim_record=$(dig +short TXT "mail._domainkey.$domain")
    
    if [ -z "$dkim_record" ]; then
        echo -e "\e[31mFAIL: No DKIM record found at mail._domainkey.$domain\e[0m"
        echo "Expected record value: v=DKIM1; k=rsa; $expected_value"
        return 1
    fi
    
    # Check if the record contains the public key
    if echo "$dkim_record" | grep -q "$expected_value"; then
        echo -e "\e[32mOK\e[0m"
        return 0
    else
        echo -e "\e[31mFAIL: DKIM record found but doesn't match expected value\e[0m"
        echo "Found: $dkim_record"
        echo "Expected to contain: $expected_value"
        return 1
    fi
}

# Function to display DNS status banner
display_dns_status_banner() {
    local has_errors=0
    
    echo "================================================================="
    echo "                      DNS VERIFICATION RESULTS                    "
    echo "================================================================="

    # First check PTR record (relevant for the server as a whole)
    echo "-----------------------------------------------------------------"
    echo "Server reverse DNS check:"
    check_ptr_record "$MAIL_HOSTNAME" || has_errors=1
    
    # Then check records for each domain
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "-----------------------------------------------------------------"
        echo "Domain: $domain"
        
        check_mx_records "$domain" "$MAIL_HOSTNAME" || has_errors=1
        check_dkim_records "$domain" || has_errors=1
    done
    
    echo "-----------------------------------------------------------------"
    if [ $has_errors -eq 1 ]; then
        echo -e "\e[33mWARNING: Some DNS records are missing or incorrect.\e[0m"
        echo "The mail forwarder will still start, but email delivery may be affected."
        echo "Please add the missing DNS records as indicated above."
    else
        echo -e "\e[32mSUCCESS: All DNS records appear to be correctly configured.\e[0m"
    fi
    echo "================================================================="
}

# Main
ensure_dig_installed
display_dns_status_banner 