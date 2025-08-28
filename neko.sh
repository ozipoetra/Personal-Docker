#!/bin/sh
if [ ! -d "/data/.config/" ]; then
  mkdir -p /data/.config
  mkdir -p /data/.ssh
fi
if [ -d "/root/.config/" ]; then
  rm -rf /root/.config/
  rm -rf /root/.ssh/
  ln -s /data/.config /root/
  ln -s /data/.ssh /root/
fi
while true
do
  gh cs ssh --codespace didactic-barnacle-pgx77wwrgrjh6pw7 -- echo "hello world"
  sleep 300
  gh cs ssh --codespace bug-free-space-telegram-w9wvv5575p63954 -- echo "hello world"
  sleep 300
  pkill gh
done
