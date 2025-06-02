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

if pgrep -x "cloudflared" > /dev/null
then
    echo "cloudflared is Running"
else
    nohup cloudflared tunnel run --token "$cloudflare_token" &
    echo "Starting cloudflared..."
fi

if pgrep -f "status.py" > /dev/null
then
    echo "status.py is running"
else
    cd /usr/local/statusx
    nohup python3 status.py &
    echo "starting status.py"
fi

if pgrep -f "aria2c" > /dev/null
then
    echo "aria2c is running"
else
    nohup aria2c --enable-rpc --rpc-listen-port=6800 --rpc-secret=nekopay &
    echo "aria2c is started"
fi

while true
do
  sleep 60
  git status
done
