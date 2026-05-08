#!/bin/sh

# 1. Setup SSH directory & key (prevents gh cs ssh auto-gen failure)
mkdir -p /home/appuser/.ssh
chmod 700 /home/appuser/.ssh
[ ! -f /home/appuser/.ssh/id_ed25519 ] && ssh-keygen -t ed25519 -f /home/appuser/.ssh/id_ed25519 -N "" -q >/dev/null 2>&1

# 2. Start lightweight HTTP health server (BusyBox compatible)
while true; do
  printf "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 >/dev/null 2>&1
done &

# 3. Run main keep-alive script (replaces this shell process)
exec /app/keepalive.sh
