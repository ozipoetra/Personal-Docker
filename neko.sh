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
  gh cs list | grep -v "NAME" | grep -v "^$" | head -n 1 | awk '{print "gh cs ssh --codespace "$1" -- hostname && exit"}' | bash
  sleep 300
  pkill gh
  gh cs list | grep -v "NAME" | grep -v "^$" | sed -n '2p' | awk '{print "gh cs ssh --codespace "$1" -- hostname && exit"}' | bash
  sleep 300
  pkill gh
done
