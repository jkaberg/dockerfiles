#!/bin/bash
set -e

# This script verifies that DNS records are correctly set up for the mail server

# Make sure environment variables are set with defaults if missing
: "${MAIL_DOMAINS:=example.com}"
: "${MAIL_HOSTNAME:=mail.example.com}"
: "${ENABLE_DKIM:=true}"
: "${VERBOSE_DNS_CHECK:=true}"  # Default to verbose for backward compatibility

# Export variables to ensure they're accessible to all functions
export MAIL_DOMAINS
export MAIL_HOSTNAME
export ENABLE_DKIM
export VERBOSE_DNS_CHECK

# Function to get the public IP address
get_public_ip() {
    # Try multiple sources to get the public IP
    PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
    echo "$PUBLIC_IP"
}

# Function to print colored status
print_status() {
    local status="$1"
    local padding="$2"
    
    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "\e[32m✅ SUCCESS\e[0m$padding"
    elif [[ "$status" == "WARNING" ]]; then
        echo -e "\e[33m⚠️  WARNING\e[0m$padding"
    elif [[ "$status" == "FAIL" ]]; then
        echo -e "\e[31m❌ FAIL\e[0m$padding"
    elif [[ "$status" == "SKIPPED" ]]; then
        echo -e "\e[33m⚠️  SKIPPED\e[0m$padding"
    else
        echo "$status$padding"
    fi
}

# Function to check PTR record
check_ptr_record() {
    local hostname="$1"
    local status=""
    local details=""
    
    # Get our public IP
    local public_ip=$(get_public_ip)
    
    if [ -z "$public_ip" ]; then
        status="SKIPPED"
        details="Could not determine public IP address"
        return 1
    fi
    
    # Get the PTR record
    local ptr_record=$(dig +short -x "$public_ip")
    
    # Remove trailing dot if present
    ptr_record="${ptr_record%.}"
    
    # Check if the PTR record matches what's expected
    if [ -z "$ptr_record" ]; then
        status="FAIL"
        details="No PTR record found for IP: $public_ip"
        return 1
    elif [[ "$ptr_record" == "$hostname" || "$ptr_record" == *"$hostname"* || "$hostname" == *"$ptr_record"* ]]; then
        status="SUCCESS"
        details="PTR: $ptr_record"
        return 0
    else
        status="WARNING"
        details="Have: $ptr_record, Need: $hostname"
        return 1
    fi
    
    echo "$status|$details"
}

# Function to check MX records
check_mx_records() {
    local domain="$1"
    local hostname="$2"
    local status=""
    local details=""
    
    # Get MX records
    mx_records=$(dig +short MX "$domain" | sort -n)
    
    # Check if any MX record points to the mail hostname
    if [ -z "$mx_records" ]; then
        status="FAIL"
        details="No MX records found"
        return 1
    elif echo "$mx_records" | grep -q "$hostname"; then
        status="SUCCESS"
        details="MX points to $hostname"
        return 0
    else
        status="WARNING"
        details="MX records exist but none point to $hostname"
        return 1
    fi
    
    echo "$status|$details"
}

# Function to check DKIM records
check_dkim_records() {
    local domain="$1"
    local status=""
    local details=""
    
    if [ "$ENABLE_DKIM" != "true" ]; then
        status="SKIPPED"
        details="DKIM disabled"
        return 0
    fi
    
    # Check if DKIM key exists locally first
    if [ ! -f "/var/mail/dkim/$domain/mail.txt" ]; then
        status="WARNING"
        details="DKIM enabled but no key found locally for $domain"
        return 1
    fi
    
    # Get the expected DKIM value (without quotation marks and header)
    expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'p=.*"' | tr -d '"')
    
    # Get the actual DKIM record
    dkim_record=$(dig +short TXT "mail._domainkey.$domain")
    
    # Check if the record contains the public key
    if [ -z "$dkim_record" ]; then
        status="FAIL"
        details="No DKIM record at mail._domainkey.$domain"
        return 1
    elif echo "$dkim_record" | grep -q "$expected_value"; then
        status="SUCCESS"
        details="DKIM correctly configured"
        return 0
    else
        status="FAIL"
        details="DKIM found but doesn't match expected value"
        return 1
    fi
    
    echo "$status|$details"
}

# Function to check SPF records
check_spf_records() {
    local domain="$1"
    local hostname="$2"
    local status=""
    local details=""
    
    # Get the SPF record
    spf_record=$(dig +short TXT "$domain" | grep "v=spf1")
    
    # Create SPF record with hostname reference but NO IP address
    local expected_record="v=spf1 mx a:$hostname ~all"
    
    # Check if the record exists and contains the hostname or mx
    if [ -z "$spf_record" ]; then
        status="FAIL"
        details="No SPF record found"
        return 1
    elif echo "$spf_record" | grep -q "$hostname" || echo "$spf_record" | grep -q "mx"; then
        status="SUCCESS"
        details="SPF includes 'mx' and/or '$hostname'"
        return 0
    else
        status="WARNING"
        details="SPF doesn't include server (need: $hostname or mx)"
        return 1
    fi
    
    echo "$status|$details"
}

# Function to check DMARC records
check_dmarc_records() {
    local domain="$1"
    local status=""
    local details=""
    
    # Get the DMARC record
    dmarc_record=$(dig +short TXT "_dmarc.$domain")
    
    # Check if the record exists and contains the expected policy
    if [ -z "$dmarc_record" ]; then
        status="FAIL"
        details="No DMARC record found at _dmarc.$domain"
        return 1
    elif echo "$dmarc_record" | grep -q "v=DMARC1"; then
        # Check the policy setting
        if echo "$dmarc_record" | grep -q "p=reject"; then
            status="SUCCESS"
            details="DMARC: p=reject (strict policy)"
        elif echo "$dmarc_record" | grep -q "p=quarantine"; then
            status="SUCCESS"
            details="DMARC: p=quarantine (moderate policy)"
        elif echo "$dmarc_record" | grep -q "p=none"; then
            status="SUCCESS"
            details="DMARC: p=none (monitoring only)"
        else
            status="WARNING"
            details="DMARC missing valid policy"
        fi
        
        # Check for reporting addresses
        if ! echo "$dmarc_record" | grep -q "rua=mailto:" && ! echo "$dmarc_record" | grep -q "ruf=mailto:"; then
            details="$details (no reporting address)"
        fi
        
        return 0
    else
        status="FAIL"
        details="Record exists but not a valid DMARC record"
        return 1
    fi
    
    echo "$status|$details"
}

# Function to display DNS status in a compact table
display_dns_status_table() {
    local has_errors=0
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                         DNS VERIFICATION RESULTS                          "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get the public IP for display
    local public_ip=$(get_public_ip)
    
    # Create header for the table
    printf "%-7s %-15s %-12s %-36s\n" "RECORD" "DOMAIN" "STATUS" "DETAILS"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    # Check PTR record first
    local ptr_status="" ptr_details=""
    check_ptr_record "$MAIL_HOSTNAME" || has_errors=1
    
    if [ $? -eq 0 ]; then
        ptr_status="SUCCESS"
        ptr_details="PTR: $(dig +short -x "$public_ip" | sed 's/\.$//')"
    else
        ptr_status="WARNING"
        ptr_details="Have: $(dig +short -x "$public_ip" | sed 's/\.$//' || echo "none"), Need: $MAIL_HOSTNAME"
        has_errors=1
    fi
    
    printf "%-7s %-15s " "PTR" "$public_ip"
    print_status "$ptr_status" " "
    printf "%-36s\n" "$ptr_details"
    
    # Process each domain
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    if [ ${#DOMAIN_ARRAY[@]} -eq 0 ]; then
        DOMAIN_ARRAY=("example.com")
    fi
    
    for domain in "${DOMAIN_ARRAY[@]}"; do
        # Check MX records
        local mx_status="" mx_details=""
        if check_mx_records "$domain" "$MAIL_HOSTNAME"; then
            mx_status="SUCCESS"
            mx_details="Points to $MAIL_HOSTNAME"
        else
            mx_status="WARNING"
            mx_details="Doesn't point to $MAIL_HOSTNAME"
            has_errors=1
        fi
        
        printf "%-7s %-15s " "MX" "$domain"
        print_status "$mx_status" " "
        printf "%-36s\n" "$mx_details"
        
        # Check SPF records
        local spf_status="" spf_details=""
        if check_spf_records "$domain" "$MAIL_HOSTNAME"; then
            spf_status="SUCCESS"
            spf_details="Includes server references"
        else
            spf_status="WARNING"
            spf_details="Missing server references"
            has_errors=1
        fi
        
        printf "%-7s %-15s " "SPF" "$domain"
        print_status "$spf_status" " "
        printf "%-36s\n" "$spf_details"
        
        # Check DMARC records
        local dmarc_status="" dmarc_details=""
        local dmarc_record=$(dig +short TXT "_dmarc.$domain" | grep "v=DMARC1")
        
        if [ -z "$dmarc_record" ]; then
            dmarc_status="FAIL"
            dmarc_details="Missing DMARC record"
            has_errors=1
        else
            dmarc_status="SUCCESS"
            if echo "$dmarc_record" | grep -q "p=reject"; then
                dmarc_details="p=reject (strict)"
            elif echo "$dmarc_record" | grep -q "p=quarantine"; then
                dmarc_details="p=quarantine (moderate)"
            elif echo "$dmarc_record" | grep -q "p=none"; then
                dmarc_details="p=none (monitoring)"
            else
                dmarc_status="WARNING"
                dmarc_details="Missing policy" 
                has_errors=1
            fi
        fi
        
        printf "%-7s %-15s " "DMARC" "$domain"
        print_status "$dmarc_status" " "
        printf "%-36s\n" "$dmarc_details"
        
        # Check DKIM records
        local dkim_status="" dkim_details=""
        if [ "$ENABLE_DKIM" != "true" ]; then
            dkim_status="SKIPPED"
            dkim_details="DKIM disabled"
        elif [ ! -f "/var/mail/dkim/$domain/mail.txt" ]; then
            dkim_status="WARNING"
            dkim_details="No DKIM key found locally"
            has_errors=1
        else
            local dkim_record=$(dig +short TXT "mail._domainkey.$domain")
            local expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" 2>/dev/null | grep -o 'p=.*"' | tr -d '"' || echo "")
            
            if [ -z "$dkim_record" ]; then
                dkim_status="FAIL"
                dkim_details="No DKIM record found"
                has_errors=1
            elif [ -n "$expected_value" ] && echo "$dkim_record" | grep -q "$expected_value"; then
                dkim_status="SUCCESS"
                dkim_details="DKIM correctly configured"
            else
                dkim_status="FAIL"
                dkim_details="DKIM doesn't match expected value"
                has_errors=1
            fi
        fi
        
        printf "%-7s %-15s " "DKIM" "$domain"
        print_status "$dkim_status" " "
        printf "%-36s\n" "$dkim_details"
        
        # Add separator between domains
        if [ "${domain}" != "${DOMAIN_ARRAY[-1]}" ]; then
            echo "───────────────────────────────────────────────────────────────────────────"
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Summary status
    if [ $has_errors -eq 1 ]; then
        echo -e "\e[33m⚠️  DNS ISSUES DETECTED: Some DNS records need attention.\e[0m"
        echo -e "\e[31m❗ Email delivery may be affected without proper DNS configuration.\e[0m"
        echo "   For a complete report, run: docker exec mail-forwarder cat /opt/dns_requirements.txt"
    else
        echo -e "\e[32m✅ ALL DNS CHECKS PASSED: Your DNS is correctly configured.\e[0m"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to show detailed recommendations
show_detailed_recommendations() {
    # Only show if VERBOSE_DNS_CHECK is true
    if [ "$VERBOSE_DNS_CHECK" = "true" ]; then
        echo ""
        echo "RECOMMENDED DNS RECORDS:"
        echo "───────────────────────────────────────────────────────────────────────────"
        local public_ip=$(get_public_ip)
        
        # PTR recommendation
        echo "PTR:    $public_ip → $MAIL_HOSTNAME (set with your hosting provider)"
        
        # Loop through domains for other records
        IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
        for domain in "${DOMAIN_ARRAY[@]}"; do
            echo ""
            echo "For $domain:"
            echo "MX:     $domain. IN MX 10 $MAIL_HOSTNAME."
            echo "SPF:    $domain. IN TXT \"v=spf1 mx a:$MAIL_HOSTNAME ~all\""
            echo "DMARC:  _dmarc.$domain. IN TXT \"v=DMARC1; p=none; rua=mailto:postmaster@$domain; pct=100\""
            
            # DKIM recommendation if enabled and key exists
            if [ "$ENABLE_DKIM" = "true" ] && [ -f "/var/mail/dkim/$domain/mail.txt" ]; then
                expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'p=.*"' | tr -d '"')
                echo "DKIM:   mail._domainkey.$domain. IN TXT \"v=DKIM1; k=rsa; $expected_value\""
            fi
        done
        echo "───────────────────────────────────────────────────────────────────────────"
        echo ""
    fi
}

# Create a summary file of DNS requirements for reference
create_dns_summary() {
    # Original summary file creation remains unchanged
    local summary_file="/opt/dns_requirements.txt"
    
    echo "DNS REQUIREMENTS FOR MAIL FORWARDER" > $summary_file
    echo "==================================" >> $summary_file
    echo "" >> $summary_file
    
    # Get our public IP
    local public_ip=$(get_public_ip)
    
    echo "1. PTR RECORD (Reverse DNS)" >> $summary_file
    echo "This must be set up with your hosting provider." >> $summary_file
    echo "For IP: $public_ip" >> $summary_file
    echo "Value: $MAIL_HOSTNAME" >> $summary_file
    echo "" >> $summary_file
    
    echo "2. MX RECORDS" >> $summary_file
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "For domain: $domain" >> $summary_file
        echo "Type: MX" >> $summary_file
        echo "Priority: 10" >> $summary_file
        echo "Value: $MAIL_HOSTNAME" >> $summary_file
        echo "Example: $domain. IN MX 10 $MAIL_HOSTNAME." >> $summary_file
        echo "" >> $summary_file
    done
    
    if [ "$ENABLE_DKIM" = "true" ]; then
        echo "3. DKIM RECORDS" >> $summary_file
        for domain in "${DOMAIN_ARRAY[@]}"; do
            if [ -f "/var/mail/dkim/$domain/mail.txt" ]; then
                expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'p=.*"' | tr -d '"')
                echo "For domain: $domain" >> $summary_file
                echo "Type: TXT" >> $summary_file
                echo "Host: mail._domainkey.$domain" >> $summary_file
                echo "Value: v=DKIM1; k=rsa; $expected_value" >> $summary_file
                echo "Example: mail._domainkey.$domain. IN TXT \"v=DKIM1; k=rsa; $expected_value\"" >> $summary_file
                echo "" >> $summary_file
            fi
        done
    fi
    
    echo "4. SPF RECORDS (REQUIRED)" >> $summary_file
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "For domain: $domain" >> $summary_file
        echo "Type: TXT" >> $summary_file
        echo "Host: $domain" >> $summary_file
        echo "Value: v=spf1 mx a:$MAIL_HOSTNAME ~all" >> $summary_file
        echo "Example: $domain. IN TXT \"v=spf1 mx a:$MAIL_HOSTNAME ~all\"" >> $summary_file
        echo "" >> $summary_file
        echo "SPF record components:" >> $summary_file
        echo "- mx: Authorizes the mail servers listed in your MX records" >> $summary_file
        echo "- a:$MAIL_HOSTNAME: Authorizes the mail server by hostname" >> $summary_file 
        echo "- ~all: Recommends rejecting mail from other sources (soft fail)" >> $summary_file
        echo "" >> $summary_file
    done
    
    echo "5. DMARC RECORDS (REQUIRED)" >> $summary_file
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "For domain: $domain" >> $summary_file
        echo "Type: TXT" >> $summary_file
        echo "Host: _dmarc.$domain" >> $summary_file
        echo "Value: v=DMARC1; p=none; rua=mailto:postmaster@$domain; pct=100" >> $summary_file
        echo "Example: _dmarc.$domain. IN TXT \"v=DMARC1; p=none; rua=mailto:postmaster@$domain; pct=100\"" >> $summary_file
        echo "" >> $summary_file
        echo "- p=none: Monitor only mode (doesn't affect delivery)" >> $summary_file
        echo "- rua=mailto:postmaster@domain: Send aggregate reports to postmaster" >> $summary_file
        echo "- pct=100: Apply to 100% of messages" >> $summary_file
        echo "" >> $summary_file
        echo "Once you've collected data and understand the impact, you can consider:" >> $summary_file
        echo "- p=quarantine: Send suspicious emails to spam folder" >> $summary_file
        echo "- p=reject: Reject suspicious emails completely" >> $summary_file
        echo "" >> $summary_file
    done
}

# Main execution
create_dns_summary
display_dns_status_table
show_detailed_recommendations 