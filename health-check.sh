#!/bin/sh

# Health check script for Docker container
# Exit 0 = healthy, Exit 1 = unhealthy

HEALTH_FILE="${HEALTH_FILE:-/tmp/health/heartbeat}"
MAX_AGE=120  # Maximum age of heartbeat file in seconds (2 minutes)
MAX_ERROR_RATE=80  # Maximum acceptable error rate percentage

# Check 1: Is the main process running?
if ! pgrep -f neko-init.sh > /dev/null; then
    echo "UNHEALTHY: neko-init.sh process not found"
    exit 1
fi

# Check 2: Does the heartbeat file exist and is it recent?
if [ ! -f "$HEALTH_FILE" ]; then
    echo "UNHEALTHY: Heartbeat file missing"
    exit 1
fi

# Check file age
current_time=$(date +%s)
file_time=$(stat -c %Y "$HEALTH_FILE" 2>/dev/null || stat -f %m "$HEALTH_FILE" 2>/dev/null)

if [ -z "$file_time" ]; then
    echo "UNHEALTHY: Cannot read heartbeat file timestamp"
    exit 1
fi

age=$((current_time - file_time))

if [ $age -gt $MAX_AGE ]; then
    echo "UNHEALTHY: Heartbeat file too old (${age}s > ${MAX_AGE}s)"
    exit 1
fi

# Check 3: Read metrics from heartbeat file and check error rate
if [ -f "$HEALTH_FILE" ]; then
    success_count=$(grep "SUCCESS_COUNT=" "$HEALTH_FILE" | cut -d= -f2)
    error_count=$(grep "ERROR_COUNT=" "$HEALTH_FILE" | cut -d= -f2)
    
    if [ -n "$success_count" ] && [ -n "$error_count" ]; then
        total=$((success_count + error_count))
        
        # Only check error rate if we have enough data points
        if [ $total -gt 10 ]; then
            error_rate=$((error_count * 100 / total))
            
            if [ $error_rate -gt $MAX_ERROR_RATE ]; then
                echo "UNHEALTHY: Error rate too high (${error_rate}% > ${MAX_ERROR_RATE}%)"
                exit 1
            fi
        fi
    fi
fi

echo "HEALTHY: All checks passed (heartbeat age: ${age}s)"
exit 0
