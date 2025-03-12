FROM debian:bookworm-slim

LABEL maintainer="Joel Kåberg <joel@kaberg.me>"
LABEL org.opencontainers.image.source="https://github.com/jkaberg/dockerfiles/mail-forwarder"
LABEL org.opencontainers.image.description="Docker-based mail forwarder and SMTP relay server"
LABEL org.opencontainers.image.licenses="MIT"

# Install required packages, create required directories, and configure permissions all in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Mail server
    postfix \
    postfix-pcre \
    # SASL authentication
    libsasl2-modules \
    sasl2-bin \
    libsasl2-2 \
    # DKIM signing
    opendkim \
    opendkim-tools \
    # Let's Encrypt/TLS
    ca-certificates \
    certbot \
    python3-certbot \
    openssl \
    # Utilities
    supervisor \
    cron \
    curl \
    dnsutils \
    tzdata \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # SASL directories
    && mkdir -p /etc/sasl2 /var/spool/postfix/etc/sasl2 \
    && chmod 750 /etc/sasl2 \
    && chmod 750 /var/spool/postfix/etc/sasl2 \
    # OpenDKIM directories
    && mkdir -p /var/run/opendkim /var/spool/postfix/opendkim /etc/opendkim/keys \
    && chown opendkim:opendkim /var/run/opendkim \
    && chown opendkim:postfix /var/spool/postfix/opendkim \
    && chown -R opendkim:opendkim /etc/opendkim \
    && chmod 750 /var/spool/postfix/opendkim \
    # Other directories
    && mkdir -p /etc/letsencrypt \
    && mkdir -p /var/mail/vhosts \
    && mkdir -p /var/mail/dkim \
    && chmod 755 /var/mail/dkim \
    # Configure postfix to log to stdout/stderr
    && (sed -i 's/^maillog_file.*/maillog_file = \/dev\/stdout/' /etc/postfix/main.cf || echo "maillog_file = /dev/stdout" >> /etc/postfix/main.cf)

# Copy configuration files
COPY scripts/ /opt/scripts/
COPY config/ /opt/config/

# Run installation script
RUN /opt/scripts/install.sh

# Set default TZ
ENV TZ=UTC

# Default mail hostname
ENV MAIL_HOSTNAME=mail.example.com

# Enable DKIM by default
ENV ENABLE_DKIM=true

# Default ACME method is TLS-ALPN
ENV ACME_METHOD=tls-alpn
ENV ALPN_PORT=587

# Only renew certificates within 7 days of expiration
ENV RENEWAL_DAYS=7

# Default exposed ports
# Port 25: Standard SMTP
# Port 465: SMTPS (SMTP over SSL)
# Port 587: Submission (SMTP with STARTTLS)
# Port 80: Only needed if using HTTP-01 challenge as fallback
EXPOSE 25 465 587 80

# Enable DNS verification by default
ENV VERIFY_DNS=true

# Volumes - only persist what's needed
VOLUME ["/etc/letsencrypt", "/var/mail/dkim"]

# Set entrypoint
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"] 