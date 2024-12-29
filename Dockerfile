FROM alpine:edge
EXPOSE 1337 22
ENV PIP_ROOT_USER_ACTION=ignore
USER root
WORKDIR /tmp
RUN apk add --no-cache shadow bash zsh zsh-autosuggestions zsh-syntax-highlighting screen supervisor nano wget curl sudo openssh bash github-cli go python3 py3-pip
RUN apk add --no-cache neofetch --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN echo 'neofetch' >> /etc/profile
RUN echo 'Welcome To Alpine Linux' > /etc/motd
RUN sh -c "$(wget https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
RUN echo "source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc && \
    echo "source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >> ~/.zshrc
RUN chsh --shell /bin/zsh root
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
    && pip install -U g4f[api] && pip install curl_cffi --upgrade --pre
WORKDIR /data
# ENTRYPOINT ["/bin/zsh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
