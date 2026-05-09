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
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
ENABLE_FAST_MONITOR="${ENABLE_FAST_MONITOR:-true}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

RETRY_SLEEP_SHORT=5
RETRY_SLEEP_LONG=30

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

# ==============================================================================
# WORKER LOGIC (SIMPLIFIED)
# ==============================================================================
run_codespace_worker() {
    local index="$1"
    local cs_name=""
    local session_start=0
    
    log_info "[Worker #$index] Starting..."

    while true; do
        # Discover codespace name
        if [ -z "$cs_name" ]; then
            cs_name=$(get_codespace_name_by_index "$index")            if [ -z "$cs_name" ]; then
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

        # ⚡ SIMPLIFIED REMOTE COMMAND:
        # Just hostname and uptime. Exits immediately. No zombies.
        local remote_cmd="echo \"\$(hostname): uptime=\$(uptime -p 2>/dev/null || uptime)\"; exit 0;"
        
        log_debug "[Worker #$index] Pinging $cs_name..."
        
        # Try to connect
        run_with_timeout 60 "gh cs ssh -c \"$cs_name\" -- \"$remote_cmd\" 2>&1"
        local exit_code=$?

        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 143 ]; then
            session_start=$(date +%s)
            log_info "[Worker #$index] Ping successful ($cs_name)"
        else
            log_warning "[Worker #$index] Connection failed (exit: $exit_code). Retrying in ${RETRY_SLEEP_SHORT}s..."
            sleep $RETRY_SLEEP_SHORT
        fi
        
        sleep 30
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

if ! gh auth status >/dev/null 2>&1; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1
fi

MONITOR_PID=""
if [ "$ENABLE_FAST_MONITOR" = "true" ]; then
    run_health_monitor &
    MONITOR_PID=$!
fi

run_codespace_worker 1 &
WORKER1_PID=$!
run_codespace_worker 2 &
WORKER2_PID=$!

log_info "Running: W1=$WORKER1_PID, W2=$WORKER2_PID, Monitor=$MONITOR_PID"

cleanup() {
    log_info "Shutting down..."
    kill "$MONITOR_PID" "$WORKER1_PID" "$WORKER2_PID" 2>/dev/null
    pkill -9 gh 2>/dev/null
    wait "$WORKER1_PID" "$WORKER2_PID" "$MONITOR_PID" 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

while true; do
    sleep 1
done
