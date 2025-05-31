#!/bin/sh
 
if command -v "cloudflared" >/dev/null 2>&1; then
  echo "cloudflared is installed."
else
  echo "cloudflare is NOT installed. Begin installing..."
  # Add cloudflare gpg key
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  # Add this repo to your apt repositories
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  # install cloudflared
  apt-get update && apt-get install cloudflared
fi

if pgrep -x "cloudflared" > /dev/null
then
    echo "cloudflared is Running"
else
    nohup cloudflared tunnel run --token "$cloudflare_token" &
    echo "Starting cloudflared..."
fi

if [ -d "/usr/local/x-ui" ]; then
  cd /usr/local/x-ui
  nohup ./x-ui &
  echo "starting x done"
fi

if pgrep -f "g4f.api.run" > /dev/null
then
    echo "g4f api is running"
else
    pip install --break-system-packages -U g4f[api] curl_cffi
    nohup python3 -m g4f.api.run &
    echo "starting g4f"
fi

while true
do
  sleep 300
  git status
done
