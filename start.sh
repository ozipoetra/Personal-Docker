#!/bin/sh
 
DIRECTORY="/workspaces/41739417"
MC_NAME="bedrock-server-1.21.82.1.zip"

if pgrep -x "openvpn" > /dev/null
then
    echo "openvpn is Running"
else
    git config --global user.name "botminecraft"
    git config --global user.email "dev@animez.my.id"
    nohup openvpn --config $DIRECTORY/bed.ovpn &
    echo "Starting openvpn..."
fi

if [ ! -d "$DIRECTORY/mc" ]; then
  echo "mc server not found, downloading..."
  mkdir -p $DIRECTORY/mc
  cd $DIRECTORY/mc
  wget --user-agent "linuxwget" https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$MC_NAME
  unzip $MC_NAME
  ln -s ../worlds worlds
  rm permissions.json
  ln -s ../permissions.json permissions.json
  rm server.properties
  ln -s ../server.properties server.properties
  nohup ./bedrock_server &
  echo "setup done, starting..."
fi

if pgrep -x "bedrock_server" > /dev/null
then
    echo "bedrock is Running"
else
    cd $DIRECTORY/mc
    nohup ./bedrock_server &
    echo "Starting bedrock..."
fi

while true
do
  sleep 300
  git status
done
