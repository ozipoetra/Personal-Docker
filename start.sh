#!/bin/sh -e
echo "root:$ROOT_PASSWORD" | chpasswd
ssh-keygen -A
exec /usr/sbin/sshd -D -e "$@"
