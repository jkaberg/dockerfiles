#!/bin/bash
set -e

# This script is run during Docker build to setup required symlinks and permissions

# Make all scripts in this directory executable
chmod +x *.sh

# Ensure the table-formatter.sh is symlinked so it can be found relative to other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ln -sf "$SCRIPT_DIR/table-formatter.sh" /opt/scripts/table-formatter.sh

# Make sure verify-dns.sh is executable
chmod +x /opt/scripts/verify-dns.sh
chmod +x /opt/scripts/configure-dkim.sh
chmod +x /opt/scripts/show-mail-config.sh
chmod +x /opt/scripts/table-formatter.sh

# Create log directory if it doesn't exist
mkdir -p /var/log/mail-forwarder

echo "Installation completed." 