FROM alpine:edge
EXPOSE 1337 22
ENV PIP_ROOT_USER_ACTION=ignore
USER root
RUN echo "root:root123" | chpasswd
WORKDIR /tmp
RUN apk add --no-cache screen supervisor nano wget curl sudo openssh bash git github-cli go python3 py3-pip
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
# RUN wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
#     && tar -xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
COPY start.sh /usr/local/bin/anu
RUN chmod +x /usr/local/bin/anu
COPY serveo.sh /usr/local/bin/serveo
RUN chmod +x /usr/local/bin/serveo
# COPY ngrok.sh /usr/local/bin/ngrokservice
# RUN chmod +x /usr/local/bin/ngrokservice
COPY supervisord.conf /etc/supervisord.conf
RUN rm -rf /tmp/*
RUN python3 -m pip config set global.break-system-packages true \
    && pip install -U g4f[api] && pip install -U curl_cffi
WORKDIR /data
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
