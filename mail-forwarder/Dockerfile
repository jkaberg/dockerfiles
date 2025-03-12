FROM debian:bookworm-slim

LABEL maintainer="Joel Kåberg <joel@kaberg.me>"
LABEL org.opencontainers.image.source="https://github.com/jkaberg/dockerfiles/mail-forwarder"
LABEL org.opencontainers.image.description="Docker-based mail forwarder and SMTP relay server"
LABEL org.opencontainers.image.licenses="MIT"

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix \
    postfix-pcre \
    ca-certificates \
    certbot \
    python3-certbot \
    python3-certbot-nginx \
    openssl \
    rsyslog \
    supervisor \
    wget \
    curl \
    tzdata \
    libsasl2-modules \
    dnsutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY scripts/ /opt/scripts/
COPY config/ /opt/config/

# Make scripts executable
RUN chmod +x /opt/scripts/*.sh

# Create required directories
RUN mkdir -p /etc/letsencrypt \
    && mkdir -p /var/mail/vhosts \
    && mkdir -p /var/mail/dkim \
    && chmod 755 /var/mail/dkim

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