FROM alpine:latest

USER root
WORKDIR /tmp

# Install hanya paket yang dibutuhkan
RUN apk add --no-cache \
    bash \
    git \
    curl \
    wget \
    sudo \
    openssh \
    ca-certificates \
    github-cli \
    nano

# Salin script init
COPY neko.sh /usr/local/bin/neko-init
RUN chmod +x /usr/local/bin/neko-init

# Bersihkan cache build
RUN rm -rf /tmp/* /var/cache/apk/*

CMD ["/usr/local/bin/neko-init"]
