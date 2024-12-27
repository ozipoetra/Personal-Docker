#!/bin/sh
# upterm host --accept bash
# echo "Install g4f depencies"
# pip install -U g4f[api]
# echo "Run g4f api"
# python3 -m g4f.api.run
ssh-keygen -A
exec /usr/sbin/sshd -D -e "$@"
