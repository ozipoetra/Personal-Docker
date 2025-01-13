FROM ubuntu:latest
EXPOSE 1337
ENV PIP_ROOT_USER_ACTION=ignore
USER root
WORKDIR /tmp
RUN apt update && apt install -y unminimize
RUN echo "y" | unminimize
RUN echo apt install -y openssh-server curl wget nano git git-lfs gh build-essential openvpn
COPY sshd_config /etc/ssh/sshd_config
RUN echo "Build Date: $(date)" > /etc/motd
# RUN wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
#     && tar -xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
COPY start.sh /usr/local/bin/mcs
RUN chmod +x /usr/local/bin/mcs
