#!/usr/bin/env bash
set -euo pipefail

PURGE=0

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: uninstall.sh [--purge]

Removes:
  - ~/.local/bin/mtproxy (wrapper)
  - the mtproxy binary inside the project directory
  - downloaded proxy lists in the Downloads directory

Options:
  --purge   also delete the entire project directory
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/mtproxy"
BINARY="$SCRIPT_DIR/mtproxy"

if command -v xdg-user-dir &>/dev/null; then
    DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
fi
if [ -z "${DOWNLOADS:-}" ] || [ "$DOWNLOADS" = "$HOME" ]; then
    DOWNLOADS="$HOME/Downloads"
fi

removed=0
for f in \
    "$WRAPPER" \
    "$BINARY" \
    "$DOWNLOADS/all_proxies.txt" \
    "$DOWNLOADS/available_proxies.txt"
do
    if [ -e "$f" ]; then
        rm -f -- "$f"
        echo "Removed: $f" >&2
        removed=$((removed + 1))
    fi
done

if [ "$PURGE" = "1" ]; then
    case "$SCRIPT_DIR" in
        "$HOME"|"/"|"")
            echo "Refusing to delete $SCRIPT_DIR" >&2
            exit 1
            ;;
    esac
    cd /
    rm -rf -- "$SCRIPT_DIR"
    echo "Removed: $SCRIPT_DIR" >&2
    removed=$((removed + 1))
fi

if [ "$removed" -eq 0 ]; then
    echo "Nothing to remove." >&2
else
    echo "Uninstall complete." >&2
fi