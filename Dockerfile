FROM ubuntu:latest
RUN apt update && \
    apt install -y openssh-server curl wget nano git git-lfs gh unzip zip openvpn sudo htop nginx python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && apt-get install -y cloudflared && \
    rm -rf /var/lib/apt/lists/*
COPY sshd_config /etc/ssh/sshd_config
RUN git clone https://github.com/dani3l0/Status /usr/local/statusx && \
    cd /usr/local/statusx && \
    pip3 install --no-cache-dir --break-system-packages -r requirements.txt
RUN echo "Build Date: $(date)" > /etc/motd
# RUN wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
#     && tar -xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
COPY start.sh /usr/local/bin/mcs
RUN chmod +x /usr/local/bin/mcs
ENTRYPOINT ["/usr/local/bin/mcs"]
