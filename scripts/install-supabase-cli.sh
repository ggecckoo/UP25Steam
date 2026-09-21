#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/.bin"
CLI="$BIN_DIR/supabase"
VERSION="v2.109.0"
ARCH="$(uname -m)"

case "$ARCH" in
  arm64) ASSET="supabase_darwin_arm64.tar.gz" ;;
  x86_64) ASSET="supabase_darwin_amd64.tar.gz" ;;
  *) echo "Desteklenmeyen mimari: $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$BIN_DIR"

if [[ -x "$CLI" ]]; then
  echo "Supabase CLI zaten kurulu: $("$CLI" --version)"
  exit 0
fi

# Prefer sibling install from 1 Song if present
SIBLING="/Users/cagataygecko/Desktop/1 Song/.bin/supabase"
if [[ -x "$SIBLING" ]]; then
  ln -sf "$SIBLING" "$CLI"
  echo "Bağlandı (1 Song): $("$CLI" --version)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/supabase/cli/releases/download/${VERSION}/${ASSET}"
echo "İndiriliyor: $URL"
curl -fsSL "$URL" -o "$TMP/supabase.tar.gz"
tar -xzf "$TMP/supabase.tar.gz" -C "$BIN_DIR"
chmod +x "$CLI"

echo "Kuruldu: $("$CLI" --version)"
