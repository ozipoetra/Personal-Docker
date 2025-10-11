#!/bin/bash

DIRECTORY="/workspaces/41739417"
# MC_NAME="bedrock-server-1.21.82.1.zip"

MOUNT_POINT="/shared"

# Cari device kedua dengan SIZE="512G"
DEVICE=$(lsblk -o NAME,SIZE -nP | awk -F'"' '$4=="512G"{count++; if(count==2) print $2}')

if [ -n "$DEVICE" ]; then
    echo "Device /dev/$DEVICE ditemukan, mencoba mount ke $MOUNT_POINT..."
    
    mkdir -p "$MOUNT_POINT"
    mount "/dev/$DEVICE" "$MOUNT_POINT"
    
    if [ $? -eq 0 ]; then
        echo "Berhasil mount /dev/$DEVICE ke $MOUNT_POINT"
    else
        echo "Gagal mount /dev/$DEVICE. Membuat symlink dari /tmp ke $MOUNT_POINT..."
        rm -rf "$MOUNT_POINT"
        ln -sfn /tmp "$MOUNT_POINT"
        echo "Symlink dibuat dari /tmp ke $MOUNT_POINT."
    fi
else
    echo "Tidak ditemukan device kedua berukuran 512G. Membuat symlink dari /tmp ke $MOUNT_POINT..."
    
    rm -rf "$MOUNT_POINT"
    ln -sfn /tmp "$MOUNT_POINT"
    echo "Symlink dibuat dari /tmp ke $MOUNT_POINT."
fi

: ' DISABLED MC SERVER & OPENVPN
if pgrep -x "openvpn" > /dev/null; then
  echo "openvpn is Running"
else
  git config --global user.name "botminecraft"
  git config --global user.email "dev@animez.my.id"
  nohup openvpn --config "$DIRECTORY/bed.ovpn" > /dev/null 2>&1 &
  echo "Starting openvpn..."
fi

if [ ! -d "$DIRECTORY/mc" ]; then
  echo "mc server not found, downloading..."
  mkdir -p "$DIRECTORY/mc"
  cd "$DIRECTORY/mc"
  wget --user-agent "linuxwget" "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$MC_NAME"
  unzip "$MC_NAME"
  ln -s ../worlds worlds
  rm -f permissions.json
  ln -s ../permissions.json permissions.json
  rm -f server.properties
  ln -s ../server.properties server.properties
  nohup ./bedrock_server > /dev/null 2>&1 &
  echo "setup done, starting..."
fi

if pgrep -x "bedrock_server" > /dev/null; then
  echo "bedrock is Running"
else
  cd "$DIRECTORY/mc"
  nohup ./bedrock_server > /dev/null 2>&1 &
  echo "Starting bedrock..."
fi
'

# Add dns server
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 9.9.9.9" >> /etc/resolv.conf

if pgrep -x "cloudflared" > /dev/null; then
  echo "cloudflared is Running"
else
  nohup cloudflared tunnel run --token "$cloudflare_token" > /dev/null 2>&1 &
  echo "Starting cloudflared..."
fi

if [ -d "/usr/local/x-ui" ]; then
  cd /usr/local/x-ui
  nohup ./x-ui &
  echo "starting x done"
fi

: ' Disable Status & Nginx & Aria2c
if pgrep -f "status.py" > /dev/null; then
  echo "status.py is running"
else
  cd /usr/local/statusx
  nohup python3 status.py > /dev/null 2>&1 &
  echo "starting status.py"
fi

if pgrep -x "nginx" > /dev/null; then
  echo "nginx is Running"
else
  nginx
  echo "Starting nginx..."
fi

if pgrep -f "aria2c" > /dev/null; then
  echo "aria2c is running"
else
  cd "$MOUNT_POINT"
  nohup aria2c --enable-rpc --rpc-listen-port=6800 --rpc-secret=nekopay > /dev/null 2>&1 &
  echo "aria2c is started"
fi

if ip link show sg10 up > /dev/null 2>&1; then
  echo "WireGuard interface sg10 is running"
else
  echo "Starting wireguard...."
  sleep 60
  mkdir -p /etc/wireguard
  cp $DIRECTORY/sg10.conf /etc/wireguard/
  # wg-quick up sg10
fi
'
