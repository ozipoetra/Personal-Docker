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
    && rm -rf /var/cache/apk/* /tmp/*

# Create non-root user (SECURITY!)
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    # Create necessary directories
    mkdir -p /app /home/appuser/.ssh && \
    chown -R appuser:appuser /app /home/appuser

# Set working directory
WORKDIR /app

# Copy script with proper ownership
COPY --chown=appuser:appuser neko.sh /app/neko-init.sh
RUN chmod +x /app/neko-init.sh

# Switch to non-root user (IMPORTANT!)
USER appuser

# Set environment variables
ENV HOME=/home/appuser \
    PATH=/app:$PATH \
    LOG_LEVEL=INFO

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f neko-init.sh || exit 1

# Run the script
CMD ["/app/neko-init.sh"]
