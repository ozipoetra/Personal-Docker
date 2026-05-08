#!/bin/sh

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Official way to pass SSH options to gh cs ssh (avoids parsing errors)
export GH_SSH_OPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=3"

MAX_RETRIES=5
HEALTH_FILE="${HEALTH_FILE:-/tmp/health/heartbeat}"

# 🔄 Keep-Alive & Lifecycle
KEEP_ALIVE_DURATION=1200        # ~20 mins per session (stays under 30m idle limit)
SESSION_ROTATION_HOURS=10       # Rotate before GitHub's 12h cap
AUTO_START_STOPPED=true
IDLE_HEARTBEAT_INTERVAL=30      # Remote echo frequency

# ⚡ Fast Health Monitor
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-10}
ENABLE_FAST_MONITOR=${ENABLE_FAST_MONITOR:-true}

LOG_LEVEL=${LOG_LEVEL:-INFO}

# ==============================================================================
# LOGGING & HEARTBEAT
# ==============================================================================
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

update_heartbeat() {
  mkdir -p "$(dirname "$HEALTH_FILE")"
  printf "TIMESTAMP=%s\nDATETIME=%s\nPID=%s\n" "$(date +%s)" "$(timestamp)" "$$" > "$HEALTH_FILE"
}

log() {
  level=$1; shift; message="$*"
  case $LOG_LEVEL in
    ERROR)    [ "$level" != "ERROR" ] && return 0 ;;
    WARNING)  [ "$level" != "ERROR" ] && [ "$level" != "WARNING" ] && return 0 ;;
    INFO)     [ "$level" = "DEBUG" ] && return 0 ;;
  esac
  printf "[%s] %-7s %s\n" "$(timestamp)" "$level" "$message"
}
log_error()   { log ERROR "$@" >&2; }
log_warning() { log WARNING "$@" >&2; }
log_info()    { log INFO "$@"; }
log_debug()   { log DEBUG "$@"; }

# ==============================================================================
# CORE UTILITIES
# ==============================================================================run_with_timeout() {
  timeout=$1; shift; cmd="$*"
  eval "$cmd" &
  pid=$!; count=0
  while kill -0 $pid 2>/dev/null; do
    if [ $count -ge $timeout ]; then
      kill -TERM $pid 2>/dev/null; sleep 2; kill -KILL $pid 2>/dev/null
      wait $pid 2>/dev/null; return 124
    fi
    sleep 1; count=$((count + 1))
  done
  wait $pid; return $?
}

# ==============================================================================
# GITHUB API HELPERS
# ==============================================================================
list_codespaces() { gh cs list --json name,state 2>/dev/null; }

get_codespace_name_by_index() {
  list_codespaces | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sed -n "${1}p"
}

get_codespace_state() {
  list_codespaces | grep -o "\"name\":\"$1\",\"state\":\"[^\"]*\"" | sed 's/.*"state":"//;s/"//'
}

wait_for_codespace_ready() {
  name=$1; max_wait=300; waited=0
  while [ $waited -lt $max_wait ]; do
    state=$(get_codespace_state "$name")
    case "$state" in
      Available) return 0 ;;
      Stopped|Shutdown|Suspended)
        if [ "$AUTO_START_STOPPED" = "true" ]; then
          log_info "[$name] Stopped. Starting..."
          gh cs start -c "$name" >/dev/null 2>&1
        else return 1; fi ;;
      Starting|Rebuilding|Updating|Creating) sleep 10 ;;
      *) return 1 ;;
    esac
    sleep 5; waited=$((waited + 15))
  done
  log_error "[$name] Timeout waiting for Available"; return 1
}

# ==============================================================================
# 🔄 WORKER LOGIC (PARALLEL)
# ==============================================================================
run_codespace_worker() {  index=$1; cs_name=""; session_start=0
  log_info "[Worker #$index] Starting..."

  while true; do
    if [ -z "$cs_name" ]; then
      cs_name=$(get_codespace_name_by_index "$index")
      if [ -z "$cs_name" ]; then sleep 30; continue; fi
      log_info "[Worker #$index] Assigned to: $cs_name"
    fi

    # Rotation check
    if [ $session_start -ne 0 ] && [ $(( $(date +%s) - session_start )) -ge $(( SESSION_ROTATION_HOURS * 3600 )) ]; then
      log_info "[Worker #$index] Rotation time reached. Reconnecting..."
      session_start=0
    fi

    # Wait for ready
    if ! wait_for_codespace_ready "$cs_name"; then sleep 30; continue; fi

    # Keep-alive command
    remote_cmd="while true; do echo \"keepalive \$(date +%s)\"; sleep $IDLE_HEARTBEAT_INTERVAL; done"
    log_debug "[Worker #$index] Starting SSH session..."
    
    # ✅ Clean gh cs ssh call
    run_with_timeout $((KEEP_ALIVE_DURATION + 30)) "gh cs ssh -c \"$cs_name\" -- \"$remote_cmd\" 2>&1"
    exit_code=$?

    if [ $exit_code -eq 0 ] || [ $exit_code -eq 124 ] || [ $exit_code -eq 143 ]; then
      session_start=$(date +%s)
      update_heartbeat
      log_info "[Worker #$index] Session OK ($cs_name)"
    else
      log_error "[Worker #$index] Failed (exit: $exit_code). Retrying..."
      sleep 30
    fi
    sleep 5
  done
}

# ==============================================================================
# ⚡ BACKGROUND HEALTH MONITOR
# ==============================================================================
run_health_monitor() {
  log_info "Fast health monitor started (interval: ${HEALTH_CHECK_INTERVAL}s)"
  while true; do
    sleep $HEALTH_CHECK_INTERVAL
    json=$(list_codespaces)
    [ -z "$json" ] && continue
    echo "$json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | while read name; do
      state=$(echo "$json" | grep "\"name\":\"$name\"" | grep -o '"state":"[^"]*"' | sed 's/"state":"//;s/"//')      if [ "$state" = "Shutdown" ] || [ "$state" = "Suspended" ] || [ "$state" = "Stopped" ]; then
        log_info "[Monitor] Auto-starting: $name"
        gh cs start -c "$name" >/dev/null 2>&1 &
      fi
    done
  done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
if [ -z "$GITHUB_TOKEN" ]; then log_error "GITHUB_TOKEN not set"; exit 1; fi

log_info "Starting Codespace Keep-Alive Manager"

gh auth status >/dev/null 2>&1 || echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1

MONITOR_PID=""
if [ "$ENABLE_FAST_MONITOR" = "true" ]; then
  run_health_monitor &; MONITOR_PID=$!
fi

run_codespace_worker 1 &; WORKER1_PID=$!
run_codespace_worker 2 &; WORKER2_PID=$!

log_info "Running: W1=$WORKER1_PID, W2=$WORKER2_PID, Monitor=$MONITOR_PID"

cleanup() {
  log_info "Shutting down..."
  kill $MONITOR_PID $WORKER1_PID $WORKER2_PID 2>/dev/null
  pkill -9 gh 2>/dev/null
  wait $WORKER1_PID $WORKER2_PID $MONITOR_PID 2>/dev/null
  rm -f "$HEALTH_FILE"; exit 0
}
trap cleanup SIGTERM SIGINT EXIT
update_heartbeat

while true; do sleep 1; done
