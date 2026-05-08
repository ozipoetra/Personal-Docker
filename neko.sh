#!/bin/sh

# Configuration
TIMEOUT_SECONDS=30
MAX_RETRIES=5
SLEEP_BETWEEN_COMMANDS=30
HEALTH_FILE="${HEALTH_FILE:-/tmp/health/heartbeat}"

# Port Forwarding Configuration (comma-separated list of port mappings)
# Format: "local:remote:visibility" where visibility is 'public' or 'private'
# Example: "4444:4444:public,8080:80:private,3000:3000:public"
PORT_FORWARDINGS="${PORT_FORWARDINGS:-}"

# ⏱️ Timeout for port forwarding commands (increased to 7 seconds)
PORT_FORWARD_TIMEOUT=7

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

# Update heartbeat file for health checks
update_heartbeat() {
  mkdir -p "$(dirname "$HEALTH_FILE")"
  cat > "$HEALTH_FILE" << EOF
TIMESTAMP=$(date +%s)
DATETIME=$(timestamp)
SUCCESS_COUNT=$SUCCESS_COUNT
ERROR_COUNT=$ERROR_COUNT
ITERATION_COUNT=$ITERATION_COUNT
UPTIME=$(($(date +%s) - LAST_SUMMARY_TIME))
PID=$$
EOF
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
  log ERROR "$@" >&2
}

log_warning() {
  log WARNING "$@" >&2
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
      update_heartbeat
      return 0
    fi
    
    log_debug "Attempting GitHub CLI login..."
    if echo "$GITHUB_TOKEN" | run_with_timeout $TIMEOUT_SECONDS "gh auth login --with-token" >/dev/null 2>&1; then
      if run_with_timeout $TIMEOUT_SECONDS "gh auth setup-git" >/dev/null 2>&1; then
        log_info "GitHub authentication setup completed"        update_heartbeat
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

# List all available codespaces
list_codespaces() {
  log_debug "Listing all codespaces..."
  local tmp=$(mktemp)

  run_with_timeout $TIMEOUT_SECONDS "gh cs list --json name,displayName,state > $tmp 2>/dev/null"
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    log_warning "Codespace list command timed out"
    rm -f "$tmp"
    return 1
  elif [ $exit_code -ne 0 ]; then
    log_warning "Failed to list codespaces (exit: $exit_code)"
    rm -f "$tmp"
    return 1
  fi

  cat "$tmp"
  rm -f "$tmp"
  return 0
}

# Parse codespace name from JSON list
get_codespace_name() {
  local json_list=$1
  local index=$2
  local name=$(echo "$json_list" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sed -n "${index}p")
  echo "$name"
}

# ============ 🔄 PORT FORWARDING FUNCTIONS ============

# Check if a port is already forwarded with correct visibility# Returns 0 if already configured correctly, 1 if needs setup
is_port_already_forwarded() {
  local codespace_name=$1
  local local_port=$2
  local desired_visibility=$3
  
  log_debug "Checking if port $local_port is already forwarded for $codespace_name"
  
  local tmp=$(mktemp)
  
  # ⏱️ Get current port forwards with 7 second timeout
  if ! run_with_timeout $PORT_FORWARD_TIMEOUT "gh cs ports -c '$codespace_name' --json sourcePort,visibility > $tmp 2>/dev/null"; then
    log_debug "Failed to fetch port list for $codespace_name"
    rm -f "$tmp"
    return 1
  fi
  
  local port_json=$(cat "$tmp")
  rm -f "$tmp"
  
  # Check if the local_port exists in the output with matching visibility
  # JSON format: [{"sourcePort":4444,"visibility":"public"},...]
  if echo "$port_json" | grep -q "\"sourcePort\":$local_port"; then
    # Port exists, check visibility
    local current_visibility=$(echo "$port_json" | grep -o "\"sourcePort\":$local_port[^}]*\"visibility\":\"[^\"]*\"" | grep -o '"visibility":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$current_visibility" = "$desired_visibility" ]; then
      log_debug "✓ Port $local_port already forwarded with visibility=$desired_visibility"
      return 0
    else
      log_debug "⚠ Port $local_port exists but visibility mismatch: current=$current_visibility, desired=$desired_visibility"
      return 1
    fi
  fi
  
  log_debug "✗ Port $local_port not found in forwarded ports list"
  return 1
}

# Forward a single port for a codespace (only if not already set)
forward_single_port() {
  local codespace_name=$1
  local local_port=$2
  local remote_port=$3
  local visibility=$4
  
  # ✅ Check if already forwarded with correct visibility - SKIP if yes!
  if is_port_already_forwarded "$codespace_name" "$local_port" "$visibility"; then
    return 0
  fi  
  log_info "Forwarding port ${local_port}:${remote_port} (${visibility}) for codespace: $codespace_name"
  
  # ⏱️ Forward the port with 7 second timeout
  if ! run_with_timeout $PORT_FORWARD_TIMEOUT "gh cs ports -c '$codespace_name' forward ${local_port}:${remote_port}" >/dev/null 2>&1; then
    log_warning "Failed to forward port ${local_port}:${remote_port} for $codespace_name"
    return 1
  fi
  
  # Set visibility if public (private is default)
  if [ "$visibility" = "public" ]; then
    if ! "gh cs ports -c '$codespace_name' visibility ${local_port}:public" >/dev/null 2>&1; then
      log_warning "Failed to set port ${local_port} to public for $codespace_name"
      return 1
    fi
    log_debug "Port ${local_port} set to public for $codespace_name"
  fi
  
  log_info "✓ Port ${local_port}:${remote_port} (${visibility}) forwarded for $codespace_name"
  return 0
}

# Forward all configured ports for a codespace
forward_ports_for_codespace() {
  local codespace_name=$1
  
  # Skip if no port forwardings configured
  if [ -z "$PORT_FORWARDINGS" ]; then
    log_debug "No port forwardings configured, skipping"
    return 0
  fi
  
  log_info "Setting up port forwarding for codespace: $codespace_name"
  
  local old_ifs="$IFS"
  IFS=','
  for port_config in $PORT_FORWARDINGS; do
    IFS="$old_ifs"
    
    # Parse local:remote:visibility
    local local_port=$(echo "$port_config" | cut -d':' -f1)
    local remote_port=$(echo "$port_config" | cut -d':' -f2)
    local visibility=$(echo "$port_config" | cut -d':' -f3)
    
    # Default visibility to private if not specified
    visibility=${visibility:-private}
    
    # Validate ports are numbers
    if ! echo "$local_port" | grep -qE '^[0-9]+$' || ! echo "$remote_port" | grep -qE '^[0-9]+$'; then
      log_warning "Invalid port configuration: $port_config (skipping)"      continue
    fi
    
    # Validate visibility value
    if [ "$visibility" != "public" ] && [ "$visibility" != "private" ]; then
      log_warning "Invalid visibility '$visibility' for port config: $port_config (defaulting to private)"
      visibility="private"
    fi
    
    # Attempt to forward with retry (only if not already set)
    local retries=0
    while [ $retries -lt 2 ]; do
      if forward_single_port "$codespace_name" "$local_port" "$remote_port" "$visibility"; then
        break
      fi
      retries=$((retries + 1))
      if [ $retries -lt 2 ]; then
        log_debug "Retrying port forward in 2 seconds..."
        sleep 2
      fi
    done
  done
  IFS="$old_ifs"
  
  return 0
}

# ============ END PORT FORWARDING FUNCTIONS ============

# Connect to codespace by name
connect_codespace_by_name() {
  local codespace_name=$1
  local index=$2
  
  if [ -z "$codespace_name" ]; then
    log_warning "Codespace #${index} not found"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    update_heartbeat
    return 1
  fi
  
  log_debug "Connecting to codespace #${index}: $codespace_name"
  
  local remote_cmd='sleep 5; exit 0'
  
  local output=$(run_with_timeout 20 gh cs ssh --codespace "$codespace_name" -- "$remote_cmd" 2>&1)
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))    update_heartbeat
    
    # Setup port forwarding after successful connection
    if [ -n "$PORT_FORWARDINGS" ]; then
      forward_ports_for_codespace "$codespace_name"
    fi
    
    if [ $((SUCCESS_COUNT % 10)) -eq 1 ] || [ $SUCCESS_COUNT -eq 1 ]; then
      log_info "Connected to codespace #${index}: $codespace_name"
      echo "$output" | while IFS= read -r line; do
        log_debug "  $line"
      done
    fi
    
    log_summary
    return 0
  elif [ $exit_code -eq 124 ]; then
    ERROR_COUNT=$((ERROR_COUNT + 1))
    update_heartbeat
    log_error "Connection to codespace #${index} timed out: $codespace_name"
    return 1
  else
    ERROR_COUNT=$((ERROR_COUNT + 1))
    update_heartbeat
    log_error "Failed to connect to codespace #${index}: $codespace_name (exit code: $exit_code)"
    if [ -n "$output" ]; then
      log_debug "Error output: $output"
    fi
    return 1
  fi
}

# Connect to codespace with retry
connect_codespace() {
  local index=$1
  local retries=0
  
  while [ $retries -lt $MAX_RETRIES ]; do
    log_debug "Attempting to connect to codespace #${index} (attempt $((retries + 1))/$MAX_RETRIES)"
    
    local codespace_json=$(list_codespaces)
    
    if [ $? -ne 0 ]; then
      log_warning "Failed to list codespaces, retrying..."
      retries=$((retries + 1))
      if [ $retries -lt $MAX_RETRIES ]; then
        sleep 5
      fi
      continue
    fi    
    local codespace_name=$(get_codespace_name "$codespace_json" "$index")
    
    if [ -z "$codespace_name" ]; then
      log_warning "Codespace #${index} not found in list"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      update_heartbeat
      return 1
    fi
    
    log_debug "Codespace #${index} name: $codespace_name"
    
    if connect_codespace_by_name "$codespace_name" "$index"; then
      return 0
    fi
    
    retries=$((retries + 1))
    if [ $retries -lt $MAX_RETRIES ]; then
      log_warning "Retrying connection in 5 seconds..."
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
  rm -f "$HEALTH_FILE"
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
log_info "Port Forwardings: ${PORT_FORWARDINGS:-none}"log_info "Port Forward Timeout: ${PORT_FORWARD_TIMEOUT}s ⏱️"
log_info "Log level: ${LOG_LEVEL}"
log_info "Health file: ${HEALTH_FILE}"

# Setup GitHub authentication
if ! setup_github_auth; then
  log_error "Failed to authenticate with GitHub"
  exit 1
fi

log_info "Service started successfully, entering main loop"

# Initial heartbeat
update_heartbeat

# Get initial list to see what we're working with
log_info "Discovering available codespaces..."
initial_list=$(list_codespaces)
codespace_count=$(echo "$initial_list" | grep -o '"name":"[^"]*"' | wc -l)
log_info "Found $codespace_count codespace(s)"

if [ "$codespace_count" -gt 0 ]; then
  log_debug "Codespace list:"
  for i in $(seq 1 $codespace_count); do
    cs_name=$(get_codespace_name "$initial_list" "$i")
    log_debug "  #$i: $cs_name"
  done
fi

# Main loop
while true; do
  ITERATION_COUNT=$((ITERATION_COUNT + 1))
  
  update_heartbeat
  
  log_debug "Starting connection attempt for codespace #1"
  connect_codespace 1
  sleep $SLEEP_BETWEEN_COMMANDS
  
  pkill -9 gh 2>/dev/null
  
  if [ "$codespace_count" -ge 2 ]; then
    log_debug "Starting connection attempt for codespace #2"
    connect_codespace 2
    sleep $SLEEP_BETWEEN_COMMANDS
    pkill -9 gh 2>/dev/null
  else
    log_debug "Only 1 codespace available, skipping codespace #2"
  fi
    sleep 5
done
