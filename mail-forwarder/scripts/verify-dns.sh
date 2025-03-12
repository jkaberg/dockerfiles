#!/bin/bash
set -e

# This script verifies that DNS records are correctly set up for the mail server

# Source our table formatter utility
if [ -f "$(dirname "$0")/table-formatter.sh" ]; then
    source "$(dirname "$0")/table-formatter.sh"
else
    echo "Error: table-formatter.sh not found. Please ensure it's in the same directory as this script."
    exit 1
fi

# Make sure environment variables are set with defaults if missing
: "${MAIL_DOMAINS:=example.com}"
: "${MAIL_HOSTNAME:=mail.example.com}"
: "${ENABLE_DKIM:=true}"
: "${VERBOSE_DNS_CHECK:=true}"  # Default to verbose for backward compatibility

# Force environment reload in case MAIL_DOMAINS was set in entrypoint.sh
if [ -f /etc/environment ]; then
    source /etc/environment
fi

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

# Print debug info about domains being checked
if [ "$VERBOSE_DNS_CHECK" = "true" ]; then
    if [ "$MAIL_DOMAINS" = "example.com" ]; then
        echo -e "\e[33m⚠️  Warning: Using default domain 'example.com'.\e[0m"
        echo -e "\e[33m⚠️  Please set MAIL_DOMAINS environment variable to your actual domains.\e[0m"
        echo -e "\e[33m⚠️  For example: MAIL_DOMAINS=kaberg.me,eth0.sh\e[0m"
        echo ""
    else
        echo "Domains being checked: $MAIL_DOMAINS"
        echo "Mail hostname: $MAIL_HOSTNAME"
        echo ""
    fi
fi

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

# Function to display DNS status in a comprehensive table
display_dns_status_table() {
    local public_ip=$1
    local has_issues=false
    local table_width=106  # Adjust based on your terminal width

    # Table header
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃                                      DNS RECORDS VERIFICATION                                      ┃"
    echo "┣━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┫"
    echo "┃ RECORD TYPE      ┃ CURRENT VALUE                   ┃ EXPECTED VALUE                  ┃ STATUS    ┃"
    echo "┣━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━┫"

    # PTR Record Check
    local ptr_record=""
    local ptr_status="✅ Valid"
    
    if [ ! -z "$public_ip" ]; then
        ptr_record=$(dig +short -x "$public_ip" 2>/dev/null | tr -d '[:space:]')
        
        # Truncate for display if needed
        local ptr_display="${ptr_record:0:30}"
        [ ${#ptr_record} -gt 30 ] && ptr_display="$ptr_display..."
        
        local expected_ptr="$MAIL_HOSTNAME."
        local expected_ptr_display="${expected_ptr:0:30}"
        [ ${#expected_ptr} -gt 30 ] && expected_ptr_display="$expected_ptr_display..."
        
        if [ -z "$ptr_record" ]; then
            ptr_status="⚠️ Missing"
            has_issues=true
        elif [[ "$ptr_record" != "$expected_ptr" ]]; then
            ptr_status="⚠️ Invalid"
            has_issues=true
        fi
        
        echo "┃ PTR (Reverse DNS) ┃ ${ptr_display:-None                           } ┃ ${expected_ptr_display:-None                           } ┃ $ptr_status ┃"
    else
        echo "┃ PTR (Reverse DNS) ┃ Cannot check - IP unknown        ┃ $MAIL_HOSTNAME.                 ┃ ⚠️ Unknown ┃"
        has_issues=true
    fi

    # Process each domain
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        # MX Record Check
        local mx_record=$(dig +short MX "$domain" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '[:space:]')
        local mx_display="${mx_record:0:30}"
        [ ${#mx_record} -gt 30 ] && mx_display="$mx_display..."
        
        local expected_mx="$MAIL_HOSTNAME."
        local expected_mx_display="${expected_mx:0:30}"
        [ ${#expected_mx} -gt 30 ] && expected_mx_display="$expected_mx_display..."
        
        local mx_status="✅ Valid"
        if [ -z "$mx_record" ]; then
            mx_status="⚠️ Missing"
            has_issues=true
        elif [[ "$mx_record" != "$expected_mx" ]]; then
            mx_status="⚠️ Invalid"
            has_issues=true
        fi
        
        echo "┃ MX for $domain" | awk -v len=16 '{printf "┃ %-16s", substr($0,3,len)}' 
        echo " ┃ ${mx_display:-None                           } ┃ ${expected_mx_display:-None                           } ┃ $mx_status ┃"
        
        # SPF Record Check
        local spf_record=$(dig +short TXT "$domain" 2>/dev/null | grep -i "v=spf1" | tr -d '"' | tr -d '[:space:]')
        local spf_display="${spf_record:0:30}"
        [ ${#spf_record} -gt 30 ] && spf_display="$spf_display..."
        
        local expected_spf="v=spf1mxa:${MAIL_HOSTNAME}~all"
        local expected_spf_display="v=spf1 mx a:$MAIL_HOSTNAME ~all"
        expected_spf_display="${expected_spf_display:0:30}"
        
        local spf_status="✅ Valid"
        if [ -z "$spf_record" ]; then
            spf_status="⚠️ Missing"
            has_issues=true
        elif [[ "$spf_record" != "$expected_spf" && "$spf_record" != "v=spf1mxa:${MAIL_HOSTNAME}-all" ]]; then
            # Check if it has the essential components (more flexible check)
            if ! echo "$spf_record" | grep -q "v=spf1" || ! echo "$spf_record" | grep -q "mx" || ! echo "$spf_record" | grep -q "${MAIL_HOSTNAME}"; then
                spf_status="⚠️ Invalid"
                has_issues=true
            fi
        fi
        
        echo "┃ SPF for $domain" | awk -v len=16 '{printf "┃ %-16s", substr($0,3,len)}' 
        echo " ┃ ${spf_display:-None                           } ┃ ${expected_spf_display:-None                           } ┃ $spf_status ┃"
        
        # DMARC Record Check
        local dmarc_record=$(dig +short TXT "_dmarc.$domain" 2>/dev/null | grep -i "v=DMARC1" | tr -d '"' | tr -d '[:space:]')
        local dmarc_display="${dmarc_record:0:30}"
        [ ${#dmarc_record} -gt 30 ] && dmarc_display="$dmarc_display..."
        
        local expected_dmarc="v=DMARC1;p=none;rua=mailto:postmaster@${domain};pct=100"
        local expected_dmarc_display="v=DMARC1; p=none; rua=mailto:postm..."
        
        local dmarc_status="✅ Valid"
        if [ -z "$dmarc_record" ]; then
            dmarc_status="⚠️ Missing"
            has_issues=true
        elif ! echo "$dmarc_record" | grep -q "v=DMARC1" || ! echo "$dmarc_record" | grep -q "p="; then
            dmarc_status="⚠️ Invalid"
            has_issues=true
        fi
        
        echo "┃ DMARC for $domain" | awk -v len=16 '{printf "┃ %-16s", substr($0,3,len)}'
        echo " ┃ ${dmarc_display:-None                           } ┃ ${expected_dmarc_display:-None                           } ┃ $dmarc_status ┃"
        
        # DKIM Record Check
        if [ "$ENABLE_DKIM" = "true" ]; then
            local selector="mail"
            local dkim_record=$(dig +short TXT "${selector}._domainkey.$domain" 2>/dev/null | tr -d '"' | tr -d '[:space:]')
            local dkim_display="${dkim_record:0:30}"
            [ ${#dkim_record} -gt 30 ] && dkim_display="$dkim_display..."
            
            local expected_dkim=""
            if [ -f "/var/mail/dkim/$domain/$selector.txt" ]; then
                expected_dkim=$(cat "/var/mail/dkim/$domain/$selector.txt" | grep -o 'v=DKIM1.*p=.*' | tr -d '[:space:]')
            fi
            local expected_dkim_display="${expected_dkim:0:30}"
            [ ${#expected_dkim} -gt 30 ] && expected_dkim_display="$expected_dkim_display..."
            
            local dkim_status="✅ Valid"
            if [ -z "$expected_dkim" ]; then
                expected_dkim_display="DKIM key not generated"
                dkim_status="⚠️ Setup needed"
                has_issues=true
            elif [ -z "$dkim_record" ]; then
                dkim_status="⚠️ Missing"
                has_issues=true
            elif ! echo "$dkim_record" | grep -q "v=DKIM1" || ! echo "$dkim_record" | grep -q "p="; then
                dkim_status="⚠️ Invalid"
                has_issues=true
            fi
            
            echo "┃ DKIM for $domain" | awk -v len=16 '{printf "┃ %-16s", substr($0,3,len)}'
            echo " ┃ ${dkim_display:-None                           } ┃ ${expected_dkim_display:-None                           } ┃ $dkim_status ┃"
        fi
    done

    # Table footer
    echo "┗━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━┛"
    
    # Summary information
    if [ "$has_issues" = true ]; then
        echo "⚠️  Some DNS records need to be updated. See file /opt/dns_requirements.txt for the exact values."
        echo "   The expected values shown above may be truncated for display purposes."
        return 1
    else
        echo "✅ All DNS records appear to be correctly configured."
        return 0
    fi
}

# Function to show all DNS recommendations in a clean, copyable format
show_full_dns_recommendations() {
    echo "COPY-PASTE READY DNS RECORDS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local public_ip=$(get_public_ip)
    
    # Print PTR recommendation
    echo "PTR RECORD (set with your hosting provider):"
    echo "$public_ip → $MAIL_HOSTNAME"
    echo ""
    
    # Process each domain
    IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        echo "RECORDS FOR DOMAIN: $domain"
        echo "───────────────────────────────────────────────────────────────────────────"
        
        # MX record
        echo "MX RECORD:"
        echo "$domain. IN MX 10 $MAIL_HOSTNAME."
        echo ""
        
        # SPF record
        echo "SPF RECORD:"
        echo "$domain. IN TXT \"v=spf1 mx a:$MAIL_HOSTNAME ~all\""
        echo ""
        
        # DMARC record
        echo "DMARC RECORD:"
        echo "_dmarc.$domain. IN TXT \"v=DMARC1; p=none; rua=mailto:postmaster@$domain; pct=100\""
        echo ""
        
        # DKIM record if enabled and key exists
        if [ "$ENABLE_DKIM" = "true" ] && [ -f "/var/mail/dkim/$domain/mail.txt" ]; then
            expected_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'v=DKIM1.*p=.*')
            if [ -n "$expected_value" ]; then
                echo "DKIM RECORD:"
                echo "mail._domainkey.$domain. IN TXT \"$expected_value\""
                echo ""
            fi
        fi
        
        if [ "${domain}" != "${DOMAIN_ARRAY[-1]}" ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
                dkim_value=$(cat "/var/mail/dkim/$domain/mail.txt" | grep -o 'v=DKIM1.*p=.*')
                echo "For domain: $domain" >> $summary_file
                echo "Type: TXT" >> $summary_file
                echo "Host: mail._domainkey.$domain" >> $summary_file
                echo "Value: $dkim_value" >> $summary_file
                echo "Example: mail._domainkey.$domain. IN TXT \"$dkim_value\"" >> $summary_file
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
verify_dns_records() {
    # Source the environment file if it exists
    if [ -f "/etc/environment" ]; then
        source /etc/environment
    fi
    
    # If MAIL_DOMAINS isn't set, try to get it from environment
    if [ -z "$MAIL_DOMAINS" ]; then
        echo "⚠️  Warning: MAIL_DOMAINS not set, checking forwarding configuration..."
        # Try to extract domains from forwarding rules
        if [ -f "/etc/postfix/virtual" ]; then
            FORWARDING_DOMAINS=$(awk -F'@' '{print $2}' /etc/postfix/virtual | awk '{print $1}' | sort -u | grep -v '^$')
            if [ ! -z "$FORWARDING_DOMAINS" ]; then
                MAIL_DOMAINS=$(echo "$FORWARDING_DOMAINS" | tr '\n' ',' | sed 's/,$//')
                echo "✅ Found domains from forwarding rules: $MAIL_DOMAINS"
            fi
        fi
    fi

    # If MAIL_HOSTNAME isn't set, try to get it from environment
    if [ -z "$MAIL_HOSTNAME" ]; then
        echo "⚠️  Warning: MAIL_HOSTNAME not set, using hostname..."
        MAIL_HOSTNAME=$(hostname -f)
    fi

    if [ -z "$MAIL_DOMAINS" ]; then
        echo "⚠️  No mail domains specified, skipping DNS verification"
        return 1
    fi

    # Create DNS summary file
    create_dns_summary

    echo "Verifying DNS configuration for domains: $MAIL_DOMAINS"
    echo "Mail server hostname: $MAIL_HOSTNAME"
    
    # Get our public IP
    local public_ip=$(get_public_ip)
    if [ -z "$public_ip" ]; then
        echo "⚠️  Warning: Could not determine public IP address, some checks may fail"
    else
        echo "Server public IP: $public_ip"
    fi
    
    # Use the create_dns_table function from table-formatter.sh
    create_dns_table "$MAIL_DOMAINS" || local has_dns_issues=true
    
    # Summary
    if [ "$has_dns_issues" = true ]; then
        echo "⚠️  DNS issues detected. Please check the DNS requirements and update your DNS settings."
        echo "    DNS requirements have been written to /opt/dns_requirements.txt"
        return 1
    else
        echo "✅ All DNS checks passed."
        return 0
    fi
}

# Main execution
verify_dns_records 