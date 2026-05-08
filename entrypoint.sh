#!/bin/sh
set -e

# Ensure .ssh directory exists with strict permissions (SSH requires 700)
mkdir -p /home/appuser/.ssh
chmod 700 /home/appuser/.ssh

# Generate a default SSH keypair if one doesn't exist
# This prevents gh cs ssh from failing during auto-generation
if [ ! -f /home/appuser/.ssh/id_ed25519 ]; then
  echo "Generating SSH keypair for gh..."
  ssh-keygen -t ed25519 -f /home/appuser/.ssh/id_ed25519 -N "" -q
fi

# Execute main script
exec /app/keepalive.sh
