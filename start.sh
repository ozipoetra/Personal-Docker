#!/bin/sh

if pgrep -x "openvpn" > /dev/null
then
    echo "openvpn is Running"
else
    nohup openvpn --config /workspaces/41739417/bed.ovpn &
    echo "Starting openvpn..."
fi

DIRECTORY="/workspaces/41739417/mc"
MC_NAME="bedrock-server-1.21.51.02.zip"

if [ ! -d "$DIRECTORY" ]; then
  mkdir -P $DIRECTORY
  cd $DIRECTORY
  wget --user-agent "linuxwget" https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$MC_NAME
  unzip $MC_NAME
  ln -s ../worlds worlds
fi

if pgrep -x "bedrock_server" > /dev/null
then
    echo "bedrock is Running"
else
    cd /workspaces/41739417/mc
    nohup ./bedrock_server &
    echo "Starting bedrock..."
fi

