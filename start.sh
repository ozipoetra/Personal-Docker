#!/bin/sh

DIRECTORY="/workspaces/41739417"
MC_NAME="bedrock-server-1.21.51.02.zip"

if pgrep -x "openvpn" > /dev/null
then
    echo "openvpn is Running"
else
    nohup openvpn --config $DIRECTORY/bed.ovpn &
    echo "Starting openvpn..."
fi

if [ ! -d "$DIRECTORY/mc" ]; then
  mkdir -P $DIRECTORY/mc
  cd $DIRECTORY/mc
  wget --user-agent "linuxwget" https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$MC_NAME
  unzip $MC_NAME
  ln -s ../worlds worlds
  ln -s ../permissions.json permissions.json
fi

if pgrep -x "bedrock_server" > /dev/null
then
    echo "bedrock is Running"
else
    cd $DIRECTORY/mc
    nohup ./bedrock_server &
    echo "Starting bedrock..."
fi

