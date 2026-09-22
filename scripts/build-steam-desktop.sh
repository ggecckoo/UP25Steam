#!/usr/bin/env bash
# Windows x64 and Steam Deck (Linux x64) builds of the desktop client.
# On a Mac it also builds a local copy so that client can be tried here.
# The macOS Steam depot remains the Swift app from build-steam-macos.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$ROOT/desktop"
GO="${GO:-$ROOT/.toolchain/go/bin/go}"
if [[ ! -x "$GO" ]]; then
  GO="go"
fi

cp "$ROOT/UP 25/L10nCatalog.json" "$DESKTOP/game/assets/L10nCatalog.json"

(
  cd "$DESKTOP"
  "$GO" test ./game
)

win="$ROOT/dist/steam-windows"
linux="$ROOT/dist/steam-linux"
mac="$ROOT/dist/desktop-macos"
mkdir -p "$win" "$linux" "$mac"
cp "$DESKTOP/cmd/2540/assets/OFL.txt" "$win/OFL.txt"
cp "$DESKTOP/cmd/2540/assets/OFL.txt" "$linux/OFL.txt"

(
  cd "$DESKTOP"
  CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
    "$GO" build -ldflags "-H=windowsgui -s -w" -o "$win/25-40.exe" ./cmd/2540
)

host="$(uname -s)"
if [[ "$host" == "Darwin" ]]; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64) goarch="amd64" ;;
    *) goarch="arm64" ;;
  esac
  (
    cd "$DESKTOP"
    CGO_ENABLED=1 GOOS=darwin GOARCH="$goarch" \
      "$GO" build -ldflags "-s -w" -o "$mac/25-40" ./cmd/2540
  )
  cp "$DESKTOP/cmd/2540/assets/OFL.txt" "$mac/OFL.txt"
fi

zig="$ROOT/.toolchain/zig-aarch64-macos-0.15.2/zig"
sysroot="$ROOT/.toolchain/linux-sysroot"
if [[ -x "$zig" && -d "$sysroot/usr/lib" ]]; then
  cat > "$ROOT/.toolchain/zig-linux-cc" << EOF
#!/bin/sh
exec "$zig" cc -target x86_64-linux-gnu.2.36 -fno-sanitize=undefined -isysroot "$sysroot" -L"$sysroot/usr/lib" -L"$sysroot/lib" "\$@"
EOF
  chmod +x "$ROOT/.toolchain/zig-linux-cc"
  cat > "$ROOT/.toolchain/pkg-config" << EOF
#!/bin/sh
case "\$*" in
  *--cflags*) echo "-I$sysroot/usr/include" ;;
  *--libs*) echo "-L$sysroot/usr/lib -lasound" ;;
  *--exists*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$ROOT/.toolchain/pkg-config"
  (
    cd "$DESKTOP"
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
      CC="$ROOT/.toolchain/zig-linux-cc" \
      PKG_CONFIG="$ROOT/.toolchain/pkg-config" \
      CGO_CFLAGS="-Wno-macro-redefined -fno-sanitize=undefined -I$sysroot/usr/include -I$sysroot/usr/include/x86_64-linux-gnu" \
      "$GO" build -ldflags "-s -w" -o "$linux/25-40" ./cmd/2540
  )
  chmod +x "$linux/25-40"
else
  echo "Linux toolchain not found; Windows build is in $win" >&2
  echo "Steam Deck build needs .toolchain/zig and .toolchain/linux-sysroot." >&2
fi

echo "Windows: $win/25-40.exe"
if [[ -x "$linux/25-40" ]]; then
  echo "Linux:   $linux/25-40"
fi
if [[ -x "$mac/25-40" ]]; then
  echo "Mac try: $mac/25-40"
fi
