FROM alpine:latest

RUN apk add --no-cache bash github-cli openssh-client curl ca-certificates procps && rm -rf /var/cache/apk/*

RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    mkdir -p /app /home/appuser/.ssh && \
    chown -R appuser:appuser /app /home/appuser && \
    chmod 700 /home/appuser/.ssh

WORKDIR /app
COPY --chown=appuser:appuser keepalive.sh /app/
COPY --chown=appuser:appuser entrypoint.sh /app/
RUN chmod +x /app/*.sh

USER appuser
ENV HOME=/home/appuser \
    PATH=/app:$PATH \
    LOG_LEVEL=INFO \
    ENABLE_FAST_MONITOR=true \
    HEALTH_CHECK_INTERVAL=10

EXPOSE 8080
CMD ["/app/entrypoint.sh"]
