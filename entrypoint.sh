#!/bin/sh

# Entrypoint script that manages both the main application and health server
# This ensures Northflank can monitor the service via HTTP health checks

LOG_PREFIX="[ENTRYPOINT]"

log_info() {
    echo "$LOG_PREFIX $@"
}

log_error() {
    echo "$LOG_PREFIX ERROR: $@" >&2
}

# Cleanup function
cleanup() {
    log_info "Shutting down services..."
    
    # Kill all child processes
    pkill -P $$ 2>/dev/null
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill if still running
    pkill -9 -P $$ 2>/dev/null
    
    log_info "Cleanup complete"
    exit 0
}

# Setup signal handlers
trap cleanup SIGTERM SIGINT

# Start the health server in background (optional, only if HTTP health checks are used)
if [ "${ENABLE_HTTP_HEALTH:-true}" = "true" ]; then
    log_info "Starting HTTP health server on port ${HEALTH_PORT:-8080}..."
    /app/health-server.sh &
    HEALTH_PID=$!
    log_info "Health server started with PID $HEALTH_PID"
fi

# Start the main application
log_info "Starting main application..."
/app/neko-init.sh &
MAIN_PID=$!
log_info "Main application started with PID $MAIN_PID"

# Monitor both processes
while true; do
    # Check if main process is still running
    if ! kill -0 $MAIN_PID 2>/dev/null; then
        log_error "Main application died unexpectedly!"
        cleanup
        exit 1
    fi
    
    # Check if health server is still running (if enabled)
    if [ "${ENABLE_HTTP_HEALTH:-true}" = "true" ] && ! kill -0 $HEALTH_PID 2>/dev/null; then
        log_error "Health server died unexpectedly!"
        # Try to restart health server
        /app/health-server.sh &
        HEALTH_PID=$!
        log_info "Health server restarted with PID $HEALTH_PID"
    fi
    
    sleep 10
done
