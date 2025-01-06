FROM alpine:edge
EXPOSE 1337
ENV PIP_ROOT_USER_ACTION=ignore
USER root
WORKDIR /tmp
RUN apk add --no-cache ca-certificates shadow bash screen supervisor nano nano-syntax wget curl sudo openssh bash github-cli go python3 py3-pip
RUN apk add --no-cache neofetch --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN echo 'neofetch' >> /etc/profile
RUN echo 'cd /data' >> /etc/profile
RUN echo 'include /usr/share/nano/*.nanorc' >> ~/.nanorc
RUN echo 'export GOCACHE="/data/.cache/go-build"' >> /etc/profile
RUN echo 'export GOMODCACHE="/data/go/pkg/mod"' >> /etc/profile
RUN echo 'export GOPATH="/data/go"' >> /etc/profile
RUN echo "Build Date: $(date)" > /etc/motd
RUN chsh --shell /bin/ash root
# RUN wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
#     && tar -xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
RUN wget https://github.com/playit-cloud/playit-agent/releases/download/v0.15.26/playit-linux-amd64 -O /usr/local/bin/playit && chmod +x /usr/local/bin/playit
COPY playits.sh /usr/local/bin/playits
RUN chmod +x /usr/local/bin/playits
COPY start.sh /usr/local/bin/anu
RUN chmod +x /usr/local/bin/anu
# COPY serveo.sh /usr/local/bin/serveo
# RUN chmod +x /usr/local/bin/serveo
# COPY ngrok.sh /usr/local/bin/ngrokservice
# RUN chmod +x /usr/local/bin/ngrokservice
COPY supervisord.conf /etc/supervisord.conf
RUN rm -rf /tmp/*
RUN python3 -m pip config set global.break-system-packages true
RUN pip install --break-system-packages -U g4f[api] curl_cffi g4f[search]
WORKDIR /data
# ENTRYPOINT ["/bin/zsh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
