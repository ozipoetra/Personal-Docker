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
  nohup gh cs ssh --codespace didactic-barnacle-pgx77wwrgrjh6pw7 > vpn.log &
  nohup gh cs ssh --codespace sturdy-bassoon-54wvvrrqxg7fp6x6 > mc.log &
  sleep 60
  pkill gh
done
