#!/bin/sh

# Simple HTTP health server for Northflank
# This runs alongside the main script and provides an HTTP endpoint
# Northflank can hit this endpoint for health checks

PORT=${HEALTH_PORT:-8080}
HEALTH_FILE="${HEALTH_FILE:-/tmp/health/heartbeat}"
MAX_AGE=120  # Maximum age of heartbeat file in seconds
MAX_ERROR_RATE=80  # Maximum acceptable error rate percentage

# Function to check health status
check_health() {
    # Check 1: Is the main process running?
    if ! pgrep -f neko-init.sh > /dev/null; then
        echo "UNHEALTHY: neko-init.sh process not found"
        return 1
    fi

    # Check 2: Does the heartbeat file exist and is it recent?
    if [ ! -f "$HEALTH_FILE" ]; then
        echo "UNHEALTHY: Heartbeat file missing"
        return 1
    fi

    # Check file age
    current_time=$(date +%s)
    file_time=$(stat -c %Y "$HEALTH_FILE" 2>/dev/null || stat -f %m "$HEALTH_FILE" 2>/dev/null)

    if [ -z "$file_time" ]; then
        echo "UNHEALTHY: Cannot read heartbeat file timestamp"
        return 1
    fi

    age=$((current_time - file_time))

    if [ $age -gt $MAX_AGE ]; then
        echo "UNHEALTHY: Heartbeat file too old (${age}s > ${MAX_AGE}s)"
        return 1
    fi

    # Check 3: Read metrics from heartbeat file
    if [ -f "$HEALTH_FILE" ]; then
        success_count=$(grep "SUCCESS_COUNT=" "$HEALTH_FILE" | cut -d= -f2)
        error_count=$(grep "ERROR_COUNT=" "$HEALTH_FILE" | cut -d= -f2)
        
        if [ -n "$success_count" ] && [ -n "$error_count" ]; then
            total=$((success_count + error_count))
            
            if [ $total -gt 10 ]; then
                error_rate=$((error_count * 100 / total))
                
                if [ $error_rate -gt $MAX_ERROR_RATE ]; then
                    echo "UNHEALTHY: Error rate too high (${error_rate}% > ${MAX_ERROR_RATE}%)"
                    return 1
                fi
            fi
        fi
    fi

    echo "HEALTHY: All checks passed (heartbeat age: ${age}s)"
    return 0
}

# Simple HTTP server using netcat
echo "Starting health server on port $PORT..."

while true; do
    # Read the HTTP request (we don't care about the content)
    response=$(check_health)
    status=$?
    
    if [ $status -eq 0 ]; then
        http_status="200 OK"
        response_body="{\"status\":\"healthy\",\"message\":\"$response\"}"
    else
        http_status="503 Service Unavailable"
        response_body="{\"status\":\"unhealthy\",\"message\":\"$response\"}"
    fi
    
    # Send HTTP response
    {
        echo "HTTP/1.1 $http_status"
        echo "Content-Type: application/json"
        echo "Connection: close"
        echo ""
        echo "$response_body"
    } | nc -l -p $PORT -q 1
done
