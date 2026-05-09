#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
export GH_SSH_OPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=3"
export GH_NO_UPDATE_NOTIFIER=1
export GH_PAGER=""

KEEP_ALIVE_DURATION="${KEEP_ALIVE_DURATION:-1200}"
SESSION_ROTATION_HOURS="${SESSION_ROTATION_HOURS:-10}"
AUTO_START_STOPPED="${AUTO_START_STOPPED:-true}"
IDLE_HEARTBEAT_INTERVAL="${IDLE_HEARTBEAT_INTERVAL:-30}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
ENABLE_FAST_MONITOR="${ENABLE_FAST_MONITOR:-true}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Fast retry settings
RETRY_SLEEP_SHORT=5   # Sleep between quick retries
RETRY_SLEEP_LONG=30   # Sleep after hard failures

# ==============================================================================
# LOGGING
# ==============================================================================
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
    local level="$1"
    shift
    local msg="$*"
    case "$LOG_LEVEL" in
        ERROR)   [[ "$level" != "ERROR" ]] && return 0 ;;
        WARNING) [[ "$level" != "ERROR" && "$level" != "WARNING" ]] && return 0 ;;
        INFO)    [[ "$level" == "DEBUG" ]] && return 0 ;;
    esac
    printf "[%s] %-7s %s\n" "$(timestamp)" "$level" "$msg"
}

log_error()   { log ERROR "$@" >&2; }
log_warning() { log WARNING "$@" >&2; }
log_info()    { log INFO "$@"; }
log_debug()   { log DEBUG "$@"; }

# ==============================================================================
# UTILITIES
# ==============================================================================
run_with_timeout() {
    local timeout_secs="$1"
    shift
    local cmd="$*"    
    eval "$cmd" &
    local pid=$!
    local count=0
    
    while kill -0 "$pid" >/dev/null 2>&1; do
        count=$((count + 1))
        if [ "$count" -ge "$timeout_secs" ]; then
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            kill -KILL "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
    done
    
    wait "$pid" 2>/dev/null
    return $?
}

# ==============================================================================
# GITHUB API HELPERS
# ==============================================================================
list_codespaces() {
    gh cs list --json name,state 2>/dev/null | tr -d ' \n\t'
}

get_codespace_name_by_index() {
    local index="$1"
    local json
    json=$(list_codespaces)
    if [ -z "$json" ]; then
        return 1
    fi
    echo "$json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sed -n "${index}p"
}

# ==============================================================================
# WORKER LOGIC (FAST WAKE-UP)
# ==============================================================================
run_codespace_worker() {
    local index="$1"
    local cs_name=""
    local session_start=0
    
    log_info "[Worker #$index] Starting..."

    while true; do
        # Discover codespace name if not set        if [ -z "$cs_name" ]; then
            cs_name=$(get_codespace_name_by_index "$index")
            if [ -z "$cs_name" ]; then
                sleep $RETRY_SLEEP_LONG
                continue
            fi
            log_info "[Worker #$index] Assigned to: $cs_name"
        fi

        # Check for session rotation
        if [ "$session_start" -ne 0 ] 2>/dev/null; then
            local now elapsed limit
            now=$(date +%s)
            elapsed=$((now - session_start))
            limit=$((SESSION_ROTATION_HOURS * 3600))
            
            if [ "$elapsed" -ge "$limit" ]; then
                log_info "[Worker #$index] Rotation time reached. Reconnecting..."
                session_start=0
            fi
        fi

        # ⚡ FAST CONNECT STRATEGY:
        # Instead of waiting for API state, we try to SSH directly.
        # gh cs ssh will auto-start the codespace if it's stopped.
        # We use a shorter timeout for the initial connection attempt.
        
        local remote_cmd="while true; do echo \"keepalive \$(date +%s)\"; sleep $IDLE_HEARTBEAT_INTERVAL; done"
        
        log_debug "[Worker #$index] Attempting SSH connection to $cs_name..."
        
        # Try to connect with a moderate timeout (60s allows for boot time)
        run_with_timeout 60 "gh cs ssh -c \"$cs_name\" -- \"$remote_cmd\" 2>&1"
        local exit_code=$?

        # Success codes: 0 (clean), 124 (timeout/kept alive), 143 (signal)
        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 143 ]; then
            session_start=$(date +%s)
            log_info "[Worker #$index] Connected to $cs_name"
            
            # Keep the session alive for the duration
            # Note: The above command already runs the keepalive loop remotely.
            # If it exits cleanly (0), it means the remote loop ended (unlikely unless killed).
            # If it times out (124), our wrapper killed it, which is expected behavior for rotation.
            
            # If we want to maintain a persistent connection like the old script,
            # we actually don't need to re-loop immediately if the SSH session is still active.
            # However, since we killed it via timeout, we restart.
            
        else            log_warning "[Worker #$index] Connection failed (exit: $exit_code). Retrying in ${RETRY_SLEEP_SHORT}s..."
            sleep $RETRY_SLEEP_SHORT
        fi
        
        # Small pause before next attempt if failed, or immediate restart if rotated
        sleep 2
    done
}

# ==============================================================================
# HEALTH MONITOR (Background)
# ==============================================================================
run_health_monitor() {
    log_info "Fast health monitor started (interval: ${HEALTH_CHECK_INTERVAL}s)"
    
    while true; do
        sleep "$HEALTH_CHECK_INTERVAL"
        
        local json
        json=$(list_codespaces)
        
        if [ -z "$json" ]; then
            continue
        fi
        
        # Parse names and check states
        local names
        names=$(echo "$json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//')
        
        while IFS= read -r cs_name; do
            if [ -z "$cs_name" ]; then
                continue
            fi
            
            local state
            state=$(echo "$json" | grep -o "\"name\":\"$cs_name\",\"state\":\"[^\"]*\"" | sed 's/.*"state":"//;s/"//')
            
            if [ "$state" = "Shutdown" ] || [ "$state" = "Suspended" ] || [ "$state" = "Stopped" ]; then
                log_info "[Monitor] Detected stopped codespace: $cs_name. Triggering start..."
                # Fire and forget start command
                gh cs start -c "$cs_name" >/dev/null 2>&1 &
            fi
        done <<< "$names"
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
if [ -z "${GITHUB_TOKEN:-}" ]; then    log_error "GITHUB_TOKEN not set"
    exit 1
fi

log_info "Starting Codespace Keep-Alive Manager"

# Authenticate
if ! gh auth status >/dev/null 2>&1; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1
fi

# Start Monitor
MONITOR_PID=""
if [ "$ENABLE_FAST_MONITOR" = "true" ]; then
    run_health_monitor &
    MONITOR_PID=$!
fi

# Start Workers
run_codespace_worker 1 &
WORKER1_PID=$!

run_codespace_worker 2 &
WORKER2_PID=$!

log_info "Running: W1=$WORKER1_PID, W2=$WORKER2_PID, Monitor=$MONITOR_PID"

# Cleanup Handler
cleanup() {
    log_info "Shutting down..."
    kill "$MONITOR_PID" "$WORKER1_PID" "$WORKER2_PID" 2>/dev/null
    pkill -9 gh 2>/dev/null
    wait "$WORKER1_PID" "$WORKER2_PID" "$MONITOR_PID" 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# Keep main process alive
while true; do
    sleep 1
done
