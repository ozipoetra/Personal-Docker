FROM alpine:latest

# Minimal dependencies only
RUN apk add --no-cache \
    github-cli \
    openssh-client \
    curl \
    ca-certificates \
    procps \
    && rm -rf /var/cache/apk/*

# Non-root user & directories
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    mkdir -p /app /tmp/health /home/appuser/.ssh && \
    chown -R appuser:appuser /app /tmp/health /home/appuser

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

# ⚡ Zero-Dependency Docker Health Check (Northflank Compatible)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD test -f "$HEALTH_FILE" && test $(($(date +%s) - $(stat -c %Y "$HEALTH_FILE" 2>/dev/null || echo 0))) -lt 120 || exit 1

CMD ["/app/entrypoint.sh"]
