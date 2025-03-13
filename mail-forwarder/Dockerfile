FROM debian:bullseye-slim

LABEL maintainer="Joel Kåberg <joel@kaberg.me>"
LABEL description="Python-based mail forwarder with DKIM, TLS support, and easy configuration"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix \
    opendkim \
    opendkim-tools \
    certbot \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    supervisor \
    ca-certificates \
    openssl \
    fail2ban \
    procps \
    dnsutils \
    curl \
    postsrsd \
    sasl2-bin \
    libsasl2-modules \
    libsasl2-modules-sql \
    libsasl2-modules-ldap \
    libsasl2-modules-gssapi-mit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up Python environment
WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /scripts /templates /etc/opendkim/keys /etc/letsencrypt /var/run/supervisor

# Create non-root user for services when possible
RUN groupadd -r mailuser && useradd -r -g mailuser mailuser

# Copy application files
COPY scripts/ /scripts/
COPY templates/ /templates/

# Set proper permissions
RUN chmod +x /scripts/*.py \
    && chown -R mailuser:mailuser /etc/opendkim/keys

# Set up volumes for persistence
VOLUME ["/etc/opendkim/keys", "/etc/letsencrypt", "/var/spool/postfix"]

# Expose mail ports
EXPOSE 25 465 587

# Set healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD /scripts/healthcheck.py

# Set entrypoint
ENTRYPOINT ["/scripts/entrypoint.py"]
CMD ["run"] 