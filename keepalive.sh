#!/bin/sh

export GH_SSH_OPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=3"
export GH_NO_UPDATE_NOTIFIER=1
export GH_PAGER=

KEEP_ALIVE_DURATION=${KEEP_ALIVE_DURATION:-1200}
SESSION_ROTATION_HOURS=${SESSION_ROTATION_HOURS:-10}
AUTO_START_STOPPED=${AUTO_START_STOPPED:-true}
IDLE_HEARTBEAT_INTERVAL=${IDLE_HEARTBEAT_INTERVAL:-30}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-10}
ENABLE_FAST_MONITOR=${ENABLE_FAST_MONITOR:-true}
LOG_LEVEL=${LOG_LEVEL:-INFO}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  level=$1
  shift
  message="$*"
  case $LOG_LEVEL in
    ERROR)
      [ "$level" != "ERROR" ] && return 0
      ;;
    WARNING)
      [ "$level" != "ERROR" ] && [ "$level" != "WARNING" ] && return 0
      ;;
    INFO)
      [ "$level" = "DEBUG" ] && return 0
      ;;
  esac
  printf "[%s] %-7s %s\n" "$(timestamp)" "$level" "$message"
}

log_error()   { log ERROR "$@" >&2; }
log_warning() { log WARNING "$@" >&2; }
log_info()    { log INFO "$@"; }
log_debug()   { log DEBUG "$@"; }

run_with_timeout() {
  _timeout="${1:-30}"
  shift
  _cmd="$*"
  eval "$_cmd" &
  _pid=$!
  _count=0
  while kill -0 "$_pid" 2>/dev/null; do
    _count=$(( _count + 1 ))    if [ "$_count" -ge "$_timeout" ] 2>/dev/null; then
      kill -TERM "$_pid" 2>/dev/null
      sleep 2
      kill -KILL "$_pid" 2>/dev/null
      wait "$_pid" 2>/dev/null
      return 124
    fi
    sleep 1
  done
  wait "$_pid" 2>/dev/null
  return $?
}

list_codespaces() {
  gh cs list --json name,state 2>/dev/null | tr -d ' \n\t'
}

get_codespace_name_by_index() {
  _json=$(list_codespaces)
  [ -z "$_json" ] && return 1
  echo "$_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sed -n "${1}p"
}

get_codespace_state() {
  _json=$(list_codespaces)
  [ -z "$_json" ] && return 1
  echo "$_json" | grep -o "\"name\":\"$1\",\"state\":\"[^\"]*\"" | sed 's/.*"state":"//;s/"//'
}

wait_for_codespace_ready() {
  _name="$1"
  _max_wait=300
  _waited=0
  while [ "$_waited" -lt "$_max_wait" ] 2>/dev/null; do
    _state=$(get_codespace_state "$_name")
    case "$_state" in
      Available) return 0 ;;
      Stopped|Shutdown|Suspended)
        if [ "$AUTO_START_STOPPED" = "true" ]; then
          log_info "$_name Stopped. Starting..."
          gh cs start -c "$_name" >/dev/null 2>&1
        else
          return 1
        fi
        ;;
      Starting|Rebuilding|Updating|Creating) sleep 10 ;;
      *) return 1 ;;
    esac
    sleep 5
    _waited=$(( _waited + 15 ))  done
  log_error "$_name Timeout waiting for Available"
  return 1
}

run_codespace_worker() {
  index="$1"
  cs_name=""
  session_start=0
  log_info "[Worker #$index] Starting..."

  while true; do
    if [ -z "$cs_name" ]; then
      cs_name=$(get_codespace_name_by_index "$index")
      if [ -z "$cs_name" ]; then
        sleep 30
        continue
      fi
      log_info "[Worker #$index] Assigned to: $cs_name"
    fi

    if [ "$session_start" != "0" ] && [ -n "$session_start" ]; then
      _now=$(date +%s)
      _elapsed=$(( _now - session_start ))
      _limit=$(( SESSION_ROTATION_HOURS * 3600 ))
      if [ "$_elapsed" -ge "$_limit" ] 2>/dev/null; then
        log_info "[Worker #$index] Rotation time reached. Reconnecting..."
        session_start=0
      fi
    fi

    if ! wait_for_codespace_ready "$cs_name"; then
      sleep 30
      continue
    fi

    remote_cmd="while true; do echo \"keepalive \$(date +%s)\"; sleep $IDLE_HEARTBEAT_INTERVAL; done"
    log_debug "[Worker #$index] Starting SSH session..."

    run_with_timeout $(( KEEP_ALIVE_DURATION + 30 )) "gh cs ssh -c \"$cs_name\" -- \"$remote_cmd\" 2>&1"
    exit_code=$?

    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 143 ]; then
      session_start=$(date +%s)
      log_info "[Worker #$index] Session OK ($cs_name)"
    else
      log_error "[Worker #$index] Failed (exit: $exit_code). Retrying..."
      sleep 30
    fi
    sleep 5  done
}

run_health_monitor() {
  log_info "Fast health monitor started (interval: ${HEALTH_CHECK_INTERVAL:-10}s)"
  while true; do
    sleep ${HEALTH_CHECK_INTERVAL:-10}
    _json=$(list_codespaces)
    [ -z "$_json" ] && continue
    echo "$_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | while read -r _cs_name; do
      _state=$(echo "$_json" | grep -o "\"name\":\"$_cs_name\",\"state\":\"[^\"]*\"" | sed 's/.*"state":"//;s/"//')
      if [ "$_state" = "Shutdown" ] || [ "$_state" = "Suspended" ] || [ "$_state" = "Stopped" ]; then
        log_info "[Monitor] Auto-starting: $_cs_name"
        gh cs start -c "$_cs_name" >/dev/null 2>&1 &
      fi
    done
  done
}

if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GITHUB_TOKEN not set"
  exit 1
fi

log_info "Starting Codespace Keep-Alive Manager"
gh auth status >/dev/null 2>&1 || echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1

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

while true; do  sleep 1
done
