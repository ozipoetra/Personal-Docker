# Use specific version instead of 'latest' for reproducibility
FROM alpine:3.22

# Install dependencies in a single layer with cleanup
RUN apk add --no-cache \
    bash \
    git \
    curl \
    openssh-client \
    ca-certificates \
    github-cli \
    procps \
    python3 \
    && rm -rf /var/cache/apk/* /tmp/*

# Create non-root user (SECURITY!)
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    # Create necessary directories
    mkdir -p /app /home/appuser/.ssh /tmp/health && \
    chown -R appuser:appuser /app /home/appuser /tmp/health

# Set working directory
WORKDIR /app

# Copy scripts with proper ownership
COPY --chown=appuser:appuser neko.sh /app/neko-init.sh
COPY --chown=appuser:appuser health-check.sh /app/health-check.sh
COPY --chown=appuser:appuser health-server.py /app/health-server.py
COPY --chown=appuser:appuser entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/neko-init.sh /app/health-check.sh /app/health-server.py /app/entrypoint.sh

# Switch to non-root user (IMPORTANT!)
USER appuser

# Set environment variables
ENV HOME=/home/appuser \
    PATH=/app:$PATH \
    LOG_LEVEL=INFO \
    HEALTH_FILE=/tmp/health/heartbeat \
    HEALTH_PORT=8080 \
    ENABLE_HTTP_HEALTH=true

# Enhanced health check for Northflank
# - Checks if script is running
# - Checks if heartbeat file is recent (updated within last 2 minutes)
# - Checks if too many errors have accumulated
# Northflank will use this for container health monitoring
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD ["/app/health-check.sh"]

# Expose health endpoint port (optional for HTTP health checks)
EXPOSE 8080

# Run the entrypoint script
CMD ["/app/entrypoint.sh"]
