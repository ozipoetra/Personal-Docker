#!/bin/sh
 
DIRECTORY="/workspaces/41739417"
MC_NAME="bedrock-server-1.21.82.1.zip"

# Target ukuran partisi
TARGET_SIZE="512G"
MOUNT_POINT="/shared"

# Daftar device yang akan dicek
DEVICES=(/dev/sda1 /dev/sdb1 /dev/sdc1)

FOUND=0

for DEV in "${DEVICES[@]}"; do
  SIZE=$(lsblk -no SIZE "$DEV" 2>/dev/null)

  if [ "$SIZE" == "$TARGET_SIZE" ]; then
    echo "Found $DEV with size $TARGET_SIZE. Mounting to $MOUNT_POINT..."
    
    # Pastikan mount point ada
    mkdir -p "$MOUNT_POINT"
    
    # Mount device (asumsi filesystem sudah cocok)
    mount "$DEV" "$MOUNT_POINT"
    
    if [ $? -eq 0 ]; then
      echo "Mounted $DEV to $MOUNT_POINT."
      FOUND=1
      break
    else
      echo "Failed to mount $DEV."
    fi
  fi
done

# Jika tidak ada partisi ditemukan, buat symlink dari /tmp
if [ $FOUND -eq 0 ]; then
  echo "No device with size $TARGET_SIZE found. Linking /tmp to $MOUNT_POINT..."
  
  # Remove existing /shared if not a mount point
  if [ -d "$MOUNT_POINT" ] && ! mountpoint -q "$MOUNT_POINT"; then
    rm -rf "$MOUNT_POINT"
  fi

  ln -sfn /tmp "$MOUNT_POINT"
  echo "Symlink created from /tmp to $MOUNT_POINT."
fi

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

if pgrep -x "nginx" > /dev/null
then
    echo "nginx is Running"
else
    nginx
    echo "Starting nginx..."
fi

if pgrep -f "aria2c" > /dev/null
then
    echo "aria2c is running"
else
    cd "$MOUNT_POINT"
    nohup aria2c --enable-rpc --rpc-listen-port=6800 --rpc-secret=nekopay &
    echo "aria2c is started"
fi

while true
do
  sleep 60
  echo -e "## THIS FILE IS DYNAMIC AND UPDATED EACH 60 SECONDS ##\n\nMSG: THIS IS TEMPORARY DISK, AND WILL BE RESETED IN : $(awk '{m=720-int($1/60); h=int(m/60); mm=m%60; if(m<1) print "now"; else { out=""; if(h>0) out=h" hours"; if(mm>0) out=out" "mm" minutes"; print out } }' /proc/uptime)" > "$MOUNT_POINT"/README.txt
done
