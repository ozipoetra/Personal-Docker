#!/bin/sh

# Pastikan GITHUB_TOKEN sudah di-set di environment
if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ GITHUB_TOKEN belum diatur. Set dengan: export GITHUB_TOKEN=your_pat_token"
  exit 1
fi

# Cek status login GitHub CLI
if ! gh auth status >/dev/null 2>&1; then
  echo "🔐 Belum login ke GitHub CLI, mencoba login..."
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  if [ $? -ne 0 ]; then
    echo "❌ Gagal login ke GitHub CLI"
    exit 1
  fi

  echo "✅ Login berhasil, menjalankan gh auth setup-git..."
  gh auth setup-git
fi

# Jalankan loop codespace
while true; do
  echo "▶️  Mengambil codespace pertama..."
  gh cs list | grep -v "NAME" | grep -v "^$" | head -n 1 | awk '{print "gh cs ssh --codespace "$1" -- hostname && exit"}' | bash
  sleep 30
  pkill gh

  echo "▶️  Mengambil codespace kedua..."
  gh cs list | grep -v "NAME" | grep -v "^$" | sed -n '2p' | awk '{print "gh cs ssh --codespace "$1" -- hostname && exit"}' | bash
  sleep 30
  pkill gh
done
