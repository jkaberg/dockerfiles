#!/bin/bash

# table-formatter.sh - Shared utility for consistent table formatting
# Usage: source this file in other scripts to access table formatting functions

# Function to create a table from input data
# Usage: create_table "Title" "Header1,Header2,Header3" "Row1Col1,Row1Col2,Row1Col3" "Row2Col1,Row2Col2,Row2Col3"
create_table() {
    local title="$1"
    local headers="$2"
    shift 2
    
    # Convert comma-separated headers to array
    IFS=',' read -ra HEADER_ARRAY <<< "$headers"
    
    # Determine the widths of each column based on headers and content
    declare -a widths
    for i in "${!HEADER_ARRAY[@]}"; do
        widths[i]=${#HEADER_ARRAY[i]}
    done
    
    # Check each row to find the maximum width needed for each column
    for row in "$@"; do
        IFS=',' read -ra FIELD_ARRAY <<< "$row"
        for i in "${!FIELD_ARRAY[@]}"; do
            if [ ${#FIELD_ARRAY[i]} -gt ${widths[i]:-0} ]; then
                widths[i]=${#FIELD_ARRAY[i]}
            fi
        done
    done
    
    # Add some padding to each column width
    for i in "${!widths[@]}"; do
        widths[i]=$((widths[i] + 2))
    done
    
    # Calculate total width of the table
    local total_width=1  # Start with 1 for the first border
    for width in "${widths[@]}"; do
        total_width=$((total_width + width + 1))  # +1 for column separator
    done
    
    # Create the title bar
    printf "┏"
    printf "%${total_width}s" | tr ' ' '━'
    printf "┓\n"
    
    # Print the title if provided
    if [ -n "$title" ]; then
        local padding=$(( (total_width - ${#title}) / 2 ))
        printf "┃%${padding}s%s%$(( total_width - padding - ${#title} ))s┃\n" "" "$title" ""
        
        # Create the divider below the title
        printf "┣"
        for i in "${!widths[@]}"; do
            printf "%${widths[i]}s" | tr ' ' '━'
            if [ $i -lt $((${#widths[@]} - 1)) ]; then
                printf "┳"
            else
                printf "┫\n"
            fi
        done
    else
        # If no title, just create top border for headers
        printf "┣"
        for i in "${!widths[@]}"; do
            printf "%${widths[i]}s" | tr ' ' '━'
            if [ $i -lt $((${#widths[@]} - 1)) ]; then
                printf "┳"
            else
                printf "┫\n"
            fi
        done
    fi
    
    # Print headers
    printf "┃"
    for i in "${!HEADER_ARRAY[@]}"; do
        printf " %-$((widths[i] - 1))s┃" "${HEADER_ARRAY[i]}"
    done
    printf "\n"
    
    # Create the divider below headers
    printf "┣"
    for i in "${!widths[@]}"; do
        printf "%${widths[i]}s" | tr ' ' '━'
        if [ $i -lt $((${#widths[@]} - 1)) ]; then
            printf "╋"
        else
            printf "┫\n"
        fi
    done
    
    # Print each row
    for row in "$@"; do
        IFS=',' read -ra FIELD_ARRAY <<< "$row"
        printf "┃"
        for i in "${!FIELD_ARRAY[@]}"; do
            printf " %-$((widths[i] - 1))s┃" "${FIELD_ARRAY[i]}"
        done
        printf "\n"
    done
    
    # Create the bottom border
    printf "┗"
    for i in "${!widths[@]}"; do
        printf "%${widths[i]}s" | tr ' ' '━'
        if [ $i -lt $((${#widths[@]} - 1)) ]; then
            printf "┻"
        else
            printf "┛\n"
        fi
    done
}

# Function to show status with color and symbol in a table
# Usage: format_status "status_text"
format_status() {
    local status="$1"
    
    case "${status,,}" in
        "valid"|"success"|"ok"|"✅")
            echo -e "\e[32m✅ Valid\e[0m"
            ;;
        "invalid"|"error"|"fail"|"❌")
            echo -e "\e[31m❌ Invalid\e[0m"
            ;;
        "missing"|"warning"|"⚠️")
            echo -e "\e[33m⚠️ Missing\e[0m"
            ;;
        "skipped")
            echo -e "\e[33m⚠️ Skipped\e[0m"
            ;;
        "unknown")
            echo -e "\e[33m⚠️ Unknown\e[0m"
            ;;
        *)
            echo "$status"
            ;;
    esac
}

# Function to truncate text for table display
# Usage: truncate_text "text" max_length
truncate_text() {
    local text="$1"
    local max_length="$2"
    
    if [ ${#text} -gt "$max_length" ]; then
        echo "${text:0:$((max_length-3))}..."
    else
        echo "$text"
    fi
}

# Function specifically for DNS records table
# Usage: create_dns_table "domain1,domain2,..."
create_dns_table() {
    local domains="$1"
    local public_ip=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || curl -s https://icanhazip.com 2>/dev/null)
    local hostname="${MAIL_HOSTNAME:-$(hostname -f)}"
    local has_issues=false
    
    # Start building the table data
    local title="DNS RECORDS VERIFICATION"
    local headers="RECORD TYPE,CURRENT VALUE,EXPECTED VALUE,STATUS"
    local rows=()
    
    # PTR Record
    if [ -n "$public_ip" ]; then
        local ptr_record=$(dig +short -x "$public_ip" 2>/dev/null | tr -d '[:space:]')
        local expected_ptr="$hostname."
        local ptr_status="valid"
        
        if [ -z "$ptr_record" ]; then
            ptr_status="missing"
            has_issues=true
        elif [[ "$ptr_record" != "$expected_ptr" ]]; then
            ptr_status="invalid"
            has_issues=true
        fi
        
        rows+=("PTR (Reverse DNS),$(truncate_text "${ptr_record:-None}" 30),$(truncate_text "$expected_ptr" 30),$(format_status "$ptr_status")")
    else
        rows+=("PTR (Reverse DNS),Cannot check - IP unknown,$hostname.,$(format_status "unknown")")
        has_issues=true
    fi
    
    # Process each domain for DNS records
    IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        [ -z "$domain" ] && continue
        
        # MX Record Check
        local mx_record=$(dig +short MX "$domain" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '[:space:]')
        local expected_mx="$hostname."
        local mx_status="valid"
        
        if [ -z "$mx_record" ]; then
            mx_status="missing"
            has_issues=true
        elif [[ "$mx_record" != "$expected_mx" ]]; then
            mx_status="invalid"
            has_issues=true
        fi
        
        rows+=("MX for $domain,$(truncate_text "${mx_record:-None}" 30),$(truncate_text "$expected_mx" 30),$(format_status "$mx_status")")
        
        # SPF Record Check
        local spf_record=$(dig +short TXT "$domain" 2>/dev/null | grep -i "v=spf1" | tr -d '"' | tr -d '[:space:]')
        local expected_spf="v=spf1 mx a:$hostname ~all"
        local expected_spf_normalized=$(echo "$expected_spf" | tr -d '[:space:]')
        local spf_status="valid"
        
        if [ -z "$spf_record" ]; then
            spf_status="missing"
            has_issues=true
        # More flexible check for SPF
        elif ! echo "$spf_record" | grep -q "v=spf1" || ! (echo "$spf_record" | grep -q "mx" || echo "$spf_record" | grep -q "$hostname"); then
            spf_status="invalid"
            has_issues=true
        fi
        
        rows+=("SPF for $domain,$(truncate_text "${spf_record:-None}" 30),$(truncate_text "$expected_spf" 30),$(format_status "$spf_status")")
        
        # DMARC Record Check
        local dmarc_record=$(dig +short TXT "_dmarc.$domain" 2>/dev/null | grep -i "v=DMARC1" | tr -d '"' | tr -d '[:space:]')
        local expected_dmarc="v=DMARC1; p=none; rua=mailto:postmaster@$domain; pct=100"
        local dmarc_status="valid"
        
        if [ -z "$dmarc_record" ]; then
            dmarc_status="missing"
            has_issues=true
        elif ! echo "$dmarc_record" | grep -q "v=DMARC1" || ! echo "$dmarc_record" | grep -q "p="; then
            dmarc_status="invalid"
            has_issues=true
        fi
        
        rows+=("DMARC for $domain,$(truncate_text "${dmarc_record:-None}" 30),$(truncate_text "$expected_dmarc" 30),$(format_status "$dmarc_status")")
        
        # DKIM Record Check if enabled
        if [ "${ENABLE_DKIM:-false}" = "true" ]; then
            local selector="mail"
            local dkim_record=$(dig +short TXT "${selector}._domainkey.$domain" 2>/dev/null | tr -d '"' | tr -d '[:space:]')
            local expected_dkim=""
            
            if [ -f "/var/mail/dkim/$domain/$selector.txt" ]; then
                expected_dkim=$(cat "/var/mail/dkim/$domain/$selector.txt" | tr -d '[:space:]')
            fi
            
            local dkim_status="valid"
            if [ -z "$expected_dkim" ]; then
                expected_dkim="DKIM key not generated"
                dkim_status="warning"
                has_issues=true
            elif [ -z "$dkim_record" ]; then
                dkim_status="missing"
                has_issues=true
            elif ! echo "$dkim_record" | grep -q "v=DKIM1" || ! echo "$dkim_record" | grep -q "p="; then
                dkim_status="invalid"
                has_issues=true
            fi
            
            rows+=("DKIM for $domain,$(truncate_text "${dkim_record:-None}" 30),$(truncate_text "$expected_dkim" 30),$(format_status "$dkim_status")")
        fi
    done
    
    # Call the create_table function with our data
    create_table "$title" "$headers" "${rows[@]}"
    
    # Return status
    if [ "$has_issues" = true ]; then
        return 1
    else
        return 0
    fi
}

# Function to create a forwarding table
# Usage: create_forwarding_table "/etc/postfix/virtual"
create_forwarding_table() {
    local virtual_file="$1"
    
    if [ ! -f "$virtual_file" ]; then
        echo "Forwarding configuration file not found: $virtual_file"
        return 1
    fi
    
    local title="EMAIL FORWARDING CONFIGURATION"
    local headers="RECIPIENT,FORWARDS TO,STATUS"
    local rows=()
    
    # Read the virtual file and create rows
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        local recipient=$(echo "$line" | awk '{print $1}')
        local destination=$(echo "$line" | awk '{print $2}')
        local status="✅ Active"
        
        rows+=("$recipient,$destination,$status")
    done < "$virtual_file"
    
    # Call the create_table function with our data
    create_table "$title" "$headers" "${rows[@]}"
    return 0
}

# Function to create a DKIM configuration table
# Usage: create_dkim_table "domain1,domain2,..."
create_dkim_table() {
    local domains="$1"
    
    local title="DKIM CONFIGURATION STATUS"
    local headers="DOMAIN,SELECTOR,KEY STATUS,DNS STATUS"
    local rows=()
    
    IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        [ -z "$domain" ] && continue
        
        local selector="mail"
        local key_status="❌ Missing"
        local dns_status="❌ Not found"
        
        # Check if key exists
        if [ -f "/var/mail/dkim/$domain/$selector.private" ]; then
            key_status="✅ Generated"
            
            # Check DNS status
            local dkim_record=$(dig +short TXT "${selector}._domainkey.$domain" 2>/dev/null)
            if [ -n "$dkim_record" ]; then
                dns_status="✅ Configured"
            else
                dns_status="⚠️ Missing in DNS"
            fi
        fi
        
        rows+=("$domain,$selector,$key_status,$dns_status")
    done
    
    # Call the create_table function with our data
    create_table "$title" "$headers" "${rows[@]}"
    return 0
} 