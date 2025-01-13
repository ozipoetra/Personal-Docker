#!/bin/sh
if pgrep -x "openvpn" > /dev/null || pgrep -x "bedrock_server" > /dev/null
then
    echo "Program is Running"
else
    nohup openvpn --config /workspaces/41739417/bed.ovpn &
    cd /workspaces/41739417/mc
    nohup ./bedrock_server &
    echo "starting..."
fi

