FROM ubuntu:latest
RUN apt update && \
    apt install -y openssh-server curl wget nano git git-lfs gh unzip zip openvpn sudo htop nginx aria2 python3 python3-pip net-tools iputils-ping wireguard && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && apt-get install -y cloudflared && \
    rm -rf /var/lib/apt/lists/*
# COPY sshd_config /etc/ssh/sshd_config
# COPY default-nginx.conf /etc/nginx/sites-available/default
RUN curl -Lo /tmp/3x-ui-install.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/refs/tags/v2.6.0/install.sh && \
    chmod +x /tmp/3x-ui-install.sh && \
    bash /tmp/3x-ui-install.sh || true
COPY x-ui.db /etc/x-ui/x-ui.db
RUN echo "Build Date: $(date)" > /etc/motd
# RUN wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
#     && tar -xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
COPY start.sh /usr/local/bin/neko-init
RUN chmod +x /usr/local/bin/neko-init
ENTRYPOINT ["/usr/local/bin/neko-init"]
