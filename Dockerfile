FROM alpine:edge
RUN mkdir -p /data
WORKDIR /data
RUN apk add --no-cache openssh tmux bash git github-cli go python3 py3-pip
RUN ssh-keygen -t ed25519 -C "root@localhost" -N '' -f ~/.ssh/id_ed25519
RUN cd /tmp && git clone https://github.com/owenthereal/upterm.git \
  && cd upterm \
  && go install ./cmd/upterm/... \
  && cd cmd/upterm \
  && go build . \
  && cp upterm /usr/local/bin/ \
  && chmod +x /usr/local/bin/upterm
RUN rm -rf /tmp
COPY start.sh /usr/local/bin/startx
RUN chmod +x /usr/local/bin/startx
EXPOSE 3000 1337
CMD ["startx"]
# ENTRYPOINT ["pip","install","-U","g4f[api]","&&","python3","-m","g4f.cli","api"]
