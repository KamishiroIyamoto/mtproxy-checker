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
  - ~/.local/bin/mtproxy (the installed program)
  - the proxy lists it downloaded and generated (names and folder are
    taken from config.go via `mtproxy --clean`)
  - leftovers from older versions

Options:
  --purge   also delete the entire project directory
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (see --help)" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
INSTALLED="$BIN_DIR/mtproxy"
LEGACY_BINARY="$SCRIPT_DIR/mtproxy"

if [ "${LANG:-}${LC_ALL:-}${LC_CTYPE:-}" != "" ] \
    && echo "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" | grep -qiE 'utf-?8' \
    && [ "${TERM:-}" != "linux" ]; then
    OK="✅"; WARN="⚠️"; BIN="🗑"
else
    OK="[OK]"; WARN="[!]"; BIN="-"
fi

say() { echo "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
is_script() { [ "$(head -c 2 "$1" 2>/dev/null)" = "#!" ]; }

find_go() {
    if have go; then
        command -v go
    elif [ -x "$HOME/.local/go/bin/go" ]; then
        echo "$HOME/.local/go/bin/go"
    fi
}

clean_lists() {
    if [ -x "$INSTALLED" ] && ! is_script "$INSTALLED"; then
        if "$INSTALLED" --clean; then
            return 0
        fi
    fi

    local go_bin
    go_bin="$(find_go)"
    if [ -n "$go_bin" ] && [ -f "$SCRIPT_DIR/go.mod" ]; then
        say "Building a temporary copy of mtproxy to find the proxy lists..."
        if (cd "$SCRIPT_DIR" && "$go_bin" run . --clean); then
            return 0
        fi
    fi
    return 1
}

if ! clean_lists; then
    say "$WARN Couldn't locate the proxy lists automatically."
    say "   If you still have them, delete them from your Downloads folder by hand."
fi

for f in "$INSTALLED" "$LEGACY_BINARY"; do
    if [ -f "$f" ]; then
        rm -f -- "$f"
        say "$BIN Removed $f"
    fi
done

if [ "$PURGE" = "1" ]; then
    case "$SCRIPT_DIR" in
        "$HOME"|"/"|"")
            say "$WARN Refusing to delete $SCRIPT_DIR"
            exit 1
            ;;
    esac
    cd /
    rm -rf -- "$SCRIPT_DIR"
    say "$BIN Removed $SCRIPT_DIR"
fi

say "$OK Uninstall complete. Thanks for using mtproxy-checker!"