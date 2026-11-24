#!/usr/bin/env bash

set -euo pipefail

URL="https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt"

if command -v xdg-user-dir &>/dev/null; then
    DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
fi
if [ -z "${DOWNLOADS:-}" ] || [ "$DOWNLOADS" = "$HOME" ]; then
    DOWNLOADS="$HOME/Downloads"
fi

INPUT="$DOWNLOADS/all_proxies.txt"
BIN="${MTPROXY_BIN:-$HOME/mtproxy-checker/mtproxy}"

mkdir -p "$DOWNLOADS"

echo "Downloading proxy list from $URL" >&2
if ! curl -fsSL --max-time 60 -o "$INPUT" "$URL"; then
    echo "Error: failed to download $URL" >&2
    exit 1
fi

if [ ! -s "$INPUT" ]; then
    echo "Error: downloaded file is empty" >&2
    exit 1
fi

if [ ! -x "$BIN" ]; then
    echo "Error: $BIN not found or not executable" >&2
    echo "Build it with: cd ~/mtproxy-checker && go build -o mtproxy ." >&2
    exit 1
fi

exec "$BIN"