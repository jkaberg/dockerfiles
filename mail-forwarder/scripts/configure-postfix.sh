#!/bin/bash
set -e

# Create an array of domains
IFS=',' read -ra DOMAIN_ARRAY <<< "$MAIL_DOMAINS"
PRIMARY_DOMAIN=${DOMAIN_ARRAY[0]}

# Configure main.cf
cat > /etc/postfix/main.cf <<EOF
# Basic configuration
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file = /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem
smtpd_tls_key_file = /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem
smtpd_tls_security_level = may
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtp_tls_note_starttls_offer = yes

# General mail parameters
myhostname = $MAIL_HOSTNAME
myorigin = \$myhostname
mydestination = \$myhostname, localhost.localdomain, localhost
mynetworks = $SMTP_NETWORKS
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# SASL configuration
smtpd_sasl_auth_enable = ${ENABLE_SMTP_AUTH}
smtpd_sasl_type = cyrus
smtpd_sasl_path = smtpd
smtpd_sasl_security_options = noanonymous
broken_sasl_auth_clients = yes

# SMTPD configuration
smtpd_helo_required = yes
smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination, reject_invalid_hostname, reject_non_fqdn_hostname, reject_non_fqdn_sender, reject_non_fqdn_recipient, reject_unknown_sender_domain, reject_unknown_recipient_domain, reject_rbl_client zen.spamhaus.org, reject_rbl_client bl.spamcop.net
smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unknown_sender_domain, reject_non_fqdn_sender

# Virtual configuration
virtual_transport = lmtp:unix:private/dovecot-lmtp
virtual_mailbox_domains = $(IFS=, ; echo "${DOMAIN_ARRAY[*]}")
virtual_mailbox_maps = hash:/etc/postfix/virtual_mailboxes
virtual_alias_maps = hash:/etc/postfix/virtual_aliases
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

# SMTP relay if configured
EOF

# Add SMTP relay configuration if provided
if [ -n "$SMTP_RELAY_HOST" ]; then
    cat >> /etc/postfix/main.cf <<EOF
# SMTP relay configuration
relayhost = [$SMTP_RELAY_HOST]:$SMTP_RELAY_PORT
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
EOF

    # Set up SASL password file
    if [ -n "$SMTP_RELAY_USERNAME" ] && [ -n "$SMTP_RELAY_PASSWORD" ]; then
        echo "[$SMTP_RELAY_HOST]:$SMTP_RELAY_PORT $SMTP_RELAY_USERNAME:$SMTP_RELAY_PASSWORD" > /etc/postfix/sasl_passwd
        chmod 600 /etc/postfix/sasl_passwd
        postmap /etc/postfix/sasl_passwd
    fi
fi

# Configure master.cf
cat > /etc/postfix/master.cf <<EOF
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (no)    (never) (100)
# ==========================================================================
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF

# Add standard services to master.cf
cat >> /etc/postfix/master.cf <<EOF
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
EOF

# Create empty virtual_mailboxes and virtual_aliases files
touch /etc/postfix/virtual_mailboxes
touch /etc/postfix/virtual_aliases

# Create /etc/aliases if it doesn't exist
if [ ! -f /etc/aliases ]; then
    echo "postmaster: root" > /etc/aliases
    echo "root: postmaster" >> /etc/aliases
fi

# Initialize the databases
postalias /etc/aliases
postmap /etc/postfix/virtual_mailboxes
postmap /etc/postfix/virtual_aliases

# Update domain configuration
echo "Domain configuration: ${DOMAIN_ARRAY[*]}"
postconf "virtual_mailbox_domains = $(IFS=, ; echo "${DOMAIN_ARRAY[*]}")" 