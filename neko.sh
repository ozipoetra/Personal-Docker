#!/bin/sh

# Configuration
TIMEOUT_SECONDS=30
MAX_RETRIES=5
SLEEP_BETWEEN_COMMANDS=30

# Log levels (can be controlled via environment variable)
LOG_LEVEL=${LOG_LEVEL:-INFO}  # DEBUG, INFO, WARNING, ERROR

# Counters for reduced logging
SUCCESS_COUNT=0
ERROR_COUNT=0
ITERATION_COUNT=0
LAST_SUMMARY_TIME=$(date +%s)
SUMMARY_INTERVAL=3600  # Log summary every hour

# Simple timestamp function
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Structured logging for Docker (JSON format optional)
log() {
  local level=$1
  shift
  local message="$@"
  
  # Check log level
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
  
  # Output to stdout (Docker will capture this)
  if [ "${LOG_FORMAT}" = "json" ]; then
    printf '{"timestamp":"%s","level":"%s","message":"%s","success_count":%d,"error_count":%d}\n' \
      "$(timestamp)" "$level" "$message" "$SUCCESS_COUNT" "$ERROR_COUNT"
  else
    printf "[%s] %-7s %s\n" "$(timestamp)" "$level" "$message"
  fi
}

log_error() {
  log ERROR "$@" >&2  # Errors to stderr
}

log_warning() {
  log WARNING "$@" >&2  # Warnings to stderr
}

log_info() {
  log INFO "$@"
}

log_debug() {
  log DEBUG "$@"
}

# Log summary periodically instead of every success
log_summary() {
  local current_time=$(date +%s)
  local elapsed=$((current_time - LAST_SUMMARY_TIME))
  
  if [ $elapsed -ge $SUMMARY_INTERVAL ]; then
    log_info "Summary: Iterations=$ITERATION_COUNT, Successes=$SUCCESS_COUNT, Errors=$ERROR_COUNT, Uptime=${elapsed}s"
    LAST_SUMMARY_TIME=$current_time
  fi
}

# Run command with timeout
run_with_timeout() {
  local timeout=$1
  shift
  local cmd="$@"
  
  eval "$cmd" &
  local pid=$!
  
  local count=0
  while kill -0 $pid 2>/dev/null; do
    if [ $count -ge $timeout ]; then
      log_warning "Command timeout after ${timeout}s, killing process..."
      kill -TERM $pid 2>/dev/null
      sleep 2
      kill -KILL $pid 2>/dev/null
      wait $pid 2>/dev/null
      return 124
    fi
    sleep 1
    count=$((count + 1))
  done
  
  wait $pid
  return $?
}

# Check GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GITHUB_TOKEN environment variable is not set"
  exit 1
fi

# Setup GitHub auth with retry
setup_github_auth() {
  local retries=0
  
  while [ $retries -lt $MAX_RETRIES ]; do
    log_debug "Checking GitHub CLI status (attempt $((retries + 1))/$MAX_RETRIES)"
    
    if run_with_timeout $TIMEOUT_SECONDS "gh auth status >/dev/null 2>&1"; then
      log_info "GitHub CLI authenticated successfully"
      return 0
    fi
    
    log_debug "Attempting GitHub CLI login..."
    if echo "$GITHUB_TOKEN" | run_with_timeout $TIMEOUT_SECONDS "gh auth login --with-token" >/dev/null 2>&1; then
      if run_with_timeout $TIMEOUT_SECONDS "gh auth setup-git" >/dev/null 2>&1; then
        log_info "GitHub authentication setup completed"
        return 0
      fi
    fi
    
    retries=$((retries + 1))
    if [ $retries -lt $MAX_RETRIES ]; then
      log_warning "Authentication failed, retrying in 5 seconds..."
      sleep 5
    fi
  done
  
  log_error "Failed to setup GitHub CLI after $MAX_RETRIES attempts"
  return 1
}

# Connect to codespace
connect_codespace() {
  local index=$1
  local retries=0
  
  while [ $retries -lt $MAX_RETRIES ]; do
    log_debug "Fetching codespace #${index} (attempt $((retries + 1))/$MAX_RETRIES)"
    
    local codespace_list=$(run_with_timeout $TIMEOUT_SECONDS "gh cs list 2>/dev/null")
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
      log_warning "Codespace list command timed out"
      retries=$((retries + 1))
      sleep 5
      continue
    elif [ $exit_code -ne 0 ]; then
      log_warning "Failed to list codespaces (exit code: $exit_code)"
      retries=$((retries + 1))
      sleep 5
      continue
    fi
    
    # Parse codespace by index
    local codespace_name=""
    if [ "$index" = "1" ]; then
      codespace_name=$(echo "$codespace_list" | grep -v "NAME" | grep -v "^$" | head -n 1 | awk '{print $1}')
    else
      codespace_name=$(echo "$codespace_list" | grep -v "NAME" | grep -v "^$" | sed -n '2p' | awk '{print $1}')
    fi
    
    if [ -z "$codespace_name" ]; then
      log_warning "Codespace #${index} not found"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      return 1
    fi
    
    log_debug "Connecting to codespace: $codespace_name"
    
    local remote_cmd='hostname_info=$(hostname); uptime_info=$(uptime -p 2>/dev/null || uptime); echo "Hostname: $hostname_info"; echo "Uptime: $uptime_info"; exit 0'
    
    local output=$(run_with_timeout $TIMEOUT_SECONDS "gh cs ssh --codespace '$codespace_name' -- '$remote_cmd' 2>&1")
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      
      # Only log detailed success occasionally (every 10th success or first success)
      if [ $((SUCCESS_COUNT % 10)) -eq 1 ] || [ $SUCCESS_COUNT -eq 1 ]; then
        log_info "Connected to codespace #${index}: $codespace_name"
        echo "$output" | while IFS= read -r line; do
          log_debug "  $line"
        done
      fi
      
      log_summary
      return 0
    else
      ERROR_COUNT=$((ERROR_COUNT + 1))
      log_error "Failed to connect to codespace #${index}: $codespace_name"
      if [ -n "$output" ]; then
        log_debug "Error output: $output"
      fi
    fi
    
    retries=$((retries + 1))
    if [ $retries -lt $MAX_RETRIES ]; then
      sleep 5
    fi
  done
  
  log_error "Exhausted retries for codespace #${index}"
  return 1
}

# Cleanup function
cleanup() {
  log_info "Cleaning up processes..."
  pkill -9 gh 2>/dev/null
  log_info "Final stats: Iterations=$ITERATION_COUNT, Successes=$SUCCESS_COUNT, Errors=$ERROR_COUNT"
}

# Graceful shutdown handler
shutdown() {
  log_info "Received shutdown signal"
  cleanup
  exit 0
}

# Setup signal handlers for graceful shutdown
trap shutdown SIGTERM SIGINT
trap cleanup EXIT

# Startup
log_info "Starting Codespace Connector Service"
log_info "Configuration: TIMEOUT=${TIMEOUT_SECONDS}s, MAX_RETRIES=${MAX_RETRIES}, SLEEP=${SLEEP_BETWEEN_COMMANDS}s"
log_info "Log level: ${LOG_LEVEL}"

# Setup GitHub authentication
if ! setup_github_auth; then
  log_error "Failed to authenticate with GitHub"
  exit 1
fi

log_info "Service started successfully, entering main loop"

# Main loop
while true; do
  ITERATION_COUNT=$((ITERATION_COUNT + 1))
  
  # Connect to codespace 1
  connect_codespace 1
  sleep $SLEEP_BETWEEN_COMMANDS
  pkill -9 gh 2>/dev/null
  
  # Connect to codespace 2
  connect_codespace 2
  sleep $SLEEP_BETWEEN_COMMANDS
  pkill -9 gh 2>/dev/null
  
  sleep 5
done
