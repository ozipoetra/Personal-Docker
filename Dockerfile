FROM alpine:3.latest

# Install minimal dependencies
RUN apk add --no-cache \
    github-cli \
    bash \
    openssh-client \
    curl \
    ca-certificates \
    procps \
    && rm -rf /var/cache/apk/*

# Create user and directories with strict permissions
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    mkdir -p /app /tmp/health /home/appuser/.ssh && \
    # Fix ownership and permissions BEFORE switching user
    chown -R appuser:appuser /app /tmp/health /home/appuser && \
    chmod 700 /home/appuser/.ssh

WORKDIR /app
COPY --chown=appuser:appuser keepalive.sh /app/
COPY --chown=appuser:appuser entrypoint.sh /app/
RUN chmod +x /app/*.sh

USER appuser

ENV HOME=/home/appuser \
    PATH=/app:$PATH \
    LOG_LEVEL=INFO \
    HEALTH_FILE=/tmp/health/heartbeat \
    ENABLE_FAST_MONITOR=true \
    HEALTH_CHECK_INTERVAL=10

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD test -f "$HEALTH_FILE" && test $(($(date +%s) - $(stat -c %Y "$HEALTH_FILE" 2>/dev/null || echo 0))) -lt 120 || exit 1

CMD ["/app/entrypoint.sh"]
