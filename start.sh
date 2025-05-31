#!/bin/sh

if pgrep -x "nginx" > /dev/null
then
    echo "nginx is Running"
else
    nginx
    echo "Starting nginx..."
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

if pgrep -f "status.py" > /dev/null
then
    echo "status.py is running"
else
    cd /usr/local/statusx
    nohup python3 status.py &
    echo "starting status.py"
fi

while true
do
  sleep 300
  git status
done
