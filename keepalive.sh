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

# ==============================================================================
# LOGGING
# ==============================================================================
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

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
    
    eval "$cmd" &    local pid=$!
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

get_codespace_state() {
    local name="$1"
    local json
    json=$(list_codespaces)
    if [ -z "$json" ]; then
        return 1
    fi
    # Extract state for specific name
    echo "$json" | grep -o "\"name\":\"$name\",\"state\":\"[^\"]*\"" | sed 's/.*"state":"//;s/"//'
}

wait_for_codespace_ready() {
    local name="$1"
    local max_wait=300    local waited=0
    
    while [ "$waited" -lt "$max_wait" ]; do
        local state
        state=$(get_codespace_state "$name")
        
        case "$state" in
            Available)
                return 0
                ;;
            Stopped|Shutdown|Suspended)
                if [ "$AUTO_START_STOPPED" = "true" ]; then
                    log_info "$name Stopped. Starting..."
                    gh cs start -c "$name" >/dev/null 2>&1
                else
                    return 1
                fi
                ;;
            Starting|Rebuilding|Updating|Creating)
                sleep 10
                ;;
            *)
                return 1
                ;;
        esac
        
        sleep 5
        waited=$((waited + 15))
    done
    
    log_error "$name Timeout waiting for Available"
    return 1
}

# ==============================================================================
# WORKER LOGIC
# ==============================================================================
run_codespace_worker() {
    local index="$1"
    local cs_name=""
    local session_start=0
    
    log_info "[Worker #$index] Starting..."

    while true; do
        # Discover codespace name if not set
        if [ -z "$cs_name" ]; then
            cs_name=$(get_codespace_name_by_index "$index")
            if [ -z "$cs_name" ]; then
                sleep 30                continue
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

        # Wait for codespace to be ready
        if ! wait_for_codespace_ready "$cs_name"; then
            sleep 30
            continue
        fi

        # Define remote keep-alive command
        local remote_cmd="while true; do echo \"keepalive \$(date +%s)\"; sleep $IDLE_HEARTBEAT_INTERVAL; done"
        
        log_debug "[Worker #$index] Starting SSH session..."
        
        # Run SSH with timeout
        run_with_timeout $((KEEP_ALIVE_DURATION + 30)) "gh cs ssh -c \"$cs_name\" -- \"$remote_cmd\" 2>&1"
        local exit_code=$?

        # Check exit code
        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 143 ]; then
            session_start=$(date +%s)
            log_info "[Worker #$index] Session OK ($cs_name)"
        else
            log_error "[Worker #$index] Failed (exit: $exit_code). Retrying..."
            sleep 30
        fi
        
        sleep 5
    done
}

# ==============================================================================
# HEALTH MONITOR
# ==============================================================================
run_health_monitor() {    log_info "Fast health monitor started (interval: ${HEALTH_CHECK_INTERVAL}s)"
    
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
                log_info "[Monitor] Auto-starting: $cs_name"
                gh cs start -c "$cs_name" >/dev/null 2>&1 &
            fi
        done <<< "$names"
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN not set"
    exit 1
fi

log_info "Starting Codespace Keep-Alive Manager"

# Authenticate
if ! gh auth status >/dev/null 2>&1; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1
fi

# Start Monitor
MONITOR_PID=""
if [ "$ENABLE_FAST_MONITOR" = "true" ]; then    run_health_monitor &
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
