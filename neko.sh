#!/bin/sh

# Configuration
TIMEOUT_SECONDS=30
MAX_RETRIES=5
SLEEP_BETWEEN_COMMANDS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_error() {
  echo "${RED}❌ $1${NC}"
}

log_success() {
  echo "${GREEN}✅ $1${NC}"
}

log_info() {
  echo "${BLUE}▶️  $1${NC}"
}

log_warning() {
  echo "${YELLOW}⚠️  $1${NC}"
}

# Fungsi untuk menjalankan command dengan timeout
run_with_timeout() {
  local timeout=$1
  shift
  local cmd="$@"
  
  # Jalankan command di background
  eval "$cmd" &
  local pid=$!
  
  # Tunggu dengan timeout
  local count=0
  while kill -0 $pid 2>/dev/null; do
    if [ $count -ge $timeout ]; then
      log_warning "Command timeout setelah ${timeout}s, membunuh proses..."
      kill -TERM $pid 2>/dev/null
      sleep 2
      kill -KILL $pid 2>/dev/null
      wait $pid 2>/dev/null
      return 124 # Timeout exit code
    fi
    sleep 1
    count=$((count + 1))
  done
  
  wait $pid
  return $?
}

# Pastikan GITHUB_TOKEN sudah di-set
if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GITHUB_TOKEN belum diatur. Set dengan: export GITHUB_TOKEN=your_pat_token"
  exit 1
fi

# Fungsi untuk setup GitHub auth dengan retry
setup_github_auth() {
  local retries=0
  
  while [ $retries -lt $MAX_RETRIES ]; do
    log_info "Memeriksa status GitHub CLI... (percobaan $((retries + 1))/$MAX_RETRIES)"
    
    if run_with_timeout $TIMEOUT_SECONDS "gh auth status >/dev/null 2>&1"; then
      log_success "Sudah login ke GitHub CLI"
      return 0
    fi
    
    log_info "Belum login, mencoba login ke GitHub CLI..."
    if echo "$GITHUB_TOKEN" | run_with_timeout $TIMEOUT_SECONDS "gh auth login --with-token"; then
      log_success "Login berhasil"
      
      log_info "Menjalankan gh auth setup-git..."
      if run_with_timeout $TIMEOUT_SECONDS "gh auth setup-git"; then
        log_success "Setup git berhasil"
        return 0
      fi
    fi
    
    retries=$((retries + 1))
    if [ $retries -lt $MAX_RETRIES ]; then
      log_warning "Gagal, mencoba lagi dalam 5 detik..."
      sleep 5
    fi
  done
  
  log_error "Gagal setup GitHub CLI setelah $MAX_RETRIES percobaan"
  return 1
}

# Fungsi untuk mendapatkan dan connect ke codespace
connect_codespace() {
  local index=$1
  local retries=0
  
  while [ $retries -lt $MAX_RETRIES ]; do
    log_info "Mengambil codespace #${index}... (percobaan $((retries + 1))/$MAX_RETRIES)"
    
    # Dapatkan list codespace dengan timeout
    local codespace_list=$(run_with_timeout $TIMEOUT_SECONDS "gh cs list 2>/dev/null")
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
      log_warning "gh cs list timeout"
      retries=$((retries + 1))
      sleep 5
      continue
    elif [ $exit_code -ne 0 ]; then
      log_error "gh cs list gagal dengan exit code $exit_code"
      retries=$((retries + 1))
      sleep 5
      continue
    fi
    
    # Parse codespace berdasarkan index
    local codespace_name=""
    if [ "$index" = "1" ]; then
      codespace_name=$(echo "$codespace_list" | grep -v "NAME" | grep -v "^$" | head -n 1 | awk '{print $1}')
    else
      codespace_name=$(echo "$codespace_list" | grep -v "NAME" | grep -v "^$" | sed -n '2p' | awk '{print $1}')
    fi
    
    if [ -z "$codespace_name" ]; then
      log_warning "Codespace #${index} tidak ditemukan"
      return 1
    fi
    
    log_info "Menghubungkan ke codespace: $codespace_name"
    
    # Connect dengan timeout
    if run_with_timeout $TIMEOUT_SECONDS "gh cs ssh --codespace $codespace_name -- 'echo "Hostname: $(hostname)" && echo "Uptime: $(uptime -p)" && exit'"; then
      log_success "Koneksi ke codespace #${index} berhasil"
      return 0
    else
      log_warning "Gagal connect ke codespace #${index}"
    fi
    
    retries=$((retries + 1))
    if [ $retries -lt $MAX_RETRIES ]; then
      sleep 5
    fi
  done
  
  log_error "Gagal connect ke codespace #${index} setelah $MAX_RETRIES percobaan"
  return 1
}

# Cleanup function
cleanup() {
  log_info "Membersihkan proses gh yang tertinggal..."
  pkill -9 gh 2>/dev/null
}

# Setup trap untuk cleanup saat script exit
trap cleanup EXIT INT TERM

# Setup GitHub authentication
if ! setup_github_auth; then
  exit 1
fi

# Main loop
log_success "Setup selesai, memulai loop codespace..."

while true; do
  # Connect ke codespace pertama
  connect_codespace 1
  sleep $SLEEP_BETWEEN_COMMANDS
  cleanup
  
  # Connect ke codespace kedua
  connect_codespace 2
  sleep $SLEEP_BETWEEN_COMMANDS
  cleanup
  
  log_info "Menunggu sebelum iterasi berikutnya..."
  sleep 5
done
