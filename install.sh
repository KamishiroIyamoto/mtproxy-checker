#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

if ! command -v go &>/dev/null; then
    echo "Error: Go not found. Install with: sudo apt install -y golang-go" >&2
    echo "Or download 1.25+ from https://go.dev/dl/" >&2
    exit 1
fi

REQUIRED_GO="1.25"
GO_VER="$(go env GOVERSION | sed 's/^go//')"
if [ "$(printf '%s\n' "$REQUIRED_GO" "$GO_VER" | sort -V | head -n1)" != "$REQUIRED_GO" ]; then
    echo "Error: Go $REQUIRED_GO or newer required, found $GO_VER" >&2
    echo "Download from https://go.dev/dl/" >&2
    exit 1
fi
if ! command -v curl &>/dev/null; then
    echo "Error: curl not found. Install with: sudo apt install -y curl" >&2
    exit 1
fi
if ! command -v xdg-user-dir &>/dev/null; then
    echo "Warning: xdg-user-dir not found. Falling back to \$HOME/Downloads." >&2
    echo "         Install with: sudo apt install -y xdg-user-dirs" >&2
fi

cd "$SCRIPT_DIR"
echo "Fetching dependencies..." >&2
go mod tidy

echo "Building mtproxy..." >&2
go build -o "$SCRIPT_DIR/mtproxy" .

mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/mtproxy.sh" "$BIN_DIR/mtproxy"
chmod +x "$BIN_DIR/mtproxy"

echo
echo "Installed:"
echo "  binary:  $SCRIPT_DIR/mtproxy"
echo "  wrapper: $BIN_DIR/mtproxy"
echo
if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    echo "NOTE: $BIN_DIR is not in your PATH."
    echo "Add this line to ~/.bashrc and restart your shell:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo "Run 'mtproxy' from anywhere."