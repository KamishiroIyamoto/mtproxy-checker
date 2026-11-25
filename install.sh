#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LOCAL_GO_DIR="$HOME/.local/go"
REQUIRED_GO="1.25"
GO_INSTALL_VERSION="${GO_INSTALL_VERSION:-1.25.0}"
PROFILE_CHANGED=0

if command -v locale >/dev/null 2>&1; then
    case "$(locale charmap 2>/dev/null)" in
        UTF-8|utf-8|UTF8|utf8) SUPPORTS_UTF8=1 ;;
        *) SUPPORTS_UTF8=0 ;;
    esac
else
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*UTF8*|*utf-8*|*utf8*) SUPPORTS_UTF8=1 ;;
        *) SUPPORTS_UTF8=0 ;;
    esac
fi
if [ "$SUPPORTS_UTF8" = "1" ]; then
    CHECK="✅"
    CROSS="❌"
else
    CHECK="[OK]"
    CROSS="[ERR]"
fi

log()  { echo "[install] $*" >&2; }
die()  { echo "[install] $CROSS error: $*" >&2; exit 1; }

version_ge() {
    awk -v a="$1" -v b="$2" '
    function num(s) { if (match(s, /^[0-9]+/)) return substr(s, 1, RLENGTH) + 0; return 0 }
    BEGIN {
        na = split(a, pa, "."); nb = split(b, pb, ".")
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            x = num(i <= na ? pa[i] : "0")
            y = num(i <= nb ? pb[i] : "0")
            if (x > y) exit 0
            if (x < y) exit 1
        }
        exit 0
    }'
}

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *)       die "Unsupported OS: $(uname -s)" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             die "Unsupported architecture: $(uname -m)" ;;
    esac
}

ensure_downloader() {
    if command -v curl >/dev/null 2>&1; then
        log "curl: found"
        return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        log "wget: found (curl not present, will use wget)"
        return 0
    fi

    log "Neither curl nor wget found; attempting to install curl..."

    local pm=""
    if command -v apt-get >/dev/null 2>&1; then
        pm="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        pm="dnf"
    elif command -v yum >/dev/null 2>&1; then
        pm="yum"
    elif command -v pacman >/dev/null 2>&1; then
        pm="pacman"
    elif command -v apk >/dev/null 2>&1; then
        pm="apk"
    elif command -v brew >/dev/null 2>&1; then
        pm="brew"
    fi

    if [ -z "$pm" ]; then
        die "No supported package manager found. Install curl or wget manually and retry."
    fi

    case "$pm" in
        apt-get)
            sudo apt-get update -qq && sudo apt-get install -y -qq curl
            ;;
        dnf)
            sudo dnf install -y -q curl
            ;;
        yum)
            sudo yum install -y -q curl
            ;;
        pacman)
            sudo pacman -S --noconfirm --quiet curl
            ;;
        apk)
            sudo apk add --no-cache curl
            ;;
        brew)
            brew install curl
            ;;
        *)
            die "Unsupported package manager: $pm"
            ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
        die "curl installation failed. Please install curl or wget manually."
    fi
    log "curl: installed"
}

download() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url"
    else
        die "Neither curl nor wget available; cannot download $url"
    fi
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

ensure_downloader

GO_OK=0
if command -v go &>/dev/null; then
    GO_VER="$(go env GOVERSION 2>/dev/null | sed 's/^go//' || true)"
    if [ -n "$GO_VER" ] && version_ge "$GO_VER" "$REQUIRED_GO"; then
        GO_OK=1
        log "Found global Go $GO_VER"
    fi
fi

if [ "$GO_OK" = "0" ] && [ -x "$LOCAL_GO_DIR/bin/go" ]; then
    export PATH="$LOCAL_GO_DIR/bin:$PATH"
    GO_VER="$(go env GOVERSION 2>/dev/null | sed 's/^go//' || true)"
    if [ -n "$GO_VER" ] && version_ge "$GO_VER" "$REQUIRED_GO"; then
        GO_OK=1
        log "Found local Go $GO_VER"
    fi
fi

if [ "$GO_OK" = "0" ]; then
    log "Installing Go $GO_INSTALL_VERSION to $LOCAL_GO_DIR"
    tarball="go${GO_INSTALL_VERSION}.${OS}-${ARCH}.tar.gz"
    url="https://go.dev/dl/${tarball}"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/$tarball"; then
        rm -rf "$tmp"
        die "Failed to download $url"
    fi

    if ! tar -C "$tmp" -xzf "$tmp/$tarball"; then
        rm -rf "$tmp"
        die "Failed to extract $tarball"
    fi
    if [ ! -d "$tmp/go" ]; then
        rm -rf "$tmp"
        die "Unexpected archive layout in $tarball"
    fi

    mkdir -p "$(dirname "$LOCAL_GO_DIR")"
    rm -rf "$LOCAL_GO_DIR"
    mv "$tmp/go" "$LOCAL_GO_DIR"
    rm -rf "$tmp"

    export PATH="$LOCAL_GO_DIR/bin:$PATH"
    GO_VER="$(go env GOVERSION 2>/dev/null | sed 's/^go//' || true)"
    if [ -z "$GO_VER" ] || ! version_ge "$GO_VER" "$REQUIRED_GO"; then
        die "Go install failed: got ${GO_VER:-unknown}, need ${REQUIRED_GO}+"
    fi
    log "Installed Go $GO_VER"
fi

detect_profile() {
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        fish) echo "$HOME/.config/fish/config.fish" ;;
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            if [ "$OS" = "darwin" ] && [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            elif [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *) echo "$HOME/.profile" ;;
    esac
}

add_to_profile() {
    local dir="$1" label="$2"
    local profile shell_name
    profile="$(detect_profile)"
    shell_name="$(basename "${SHELL:-bash}")"

    if [ -f "$profile" ] && grep -qF "$dir" "$profile" 2>/dev/null; then
        log "$label: $dir already present in $profile"
        return 1
    fi

    mkdir -p "$(dirname "$profile")"
    {
        echo ""
        echo "# Added by mtproxy-checker installer ($label)"
        if [ "$shell_name" = "fish" ]; then
            echo "fish_add_path \"$dir\""
        else
            echo "export PATH=\"$dir:\$PATH\""
        fi
    } >> "$profile"
    PROFILE_CHANGED=1
    log "$label: added $dir to $profile"
    return 0
}

if [ -x "$LOCAL_GO_DIR/bin/go" ]; then
    case "$(command -v go || true)" in
        "$LOCAL_GO_DIR/bin/go") add_to_profile "$LOCAL_GO_DIR/bin" "go" || true ;;
    esac
fi

cd "$SCRIPT_DIR"
log "Fetching dependencies (go mod tidy)..."
GO111MODULE=on go mod tidy
log "Building mtproxy..."
if ! GO111MODULE=on go build -o "$SCRIPT_DIR/mtproxy" .; then
    die "go build failed"
fi

mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/mtproxy.sh" "$BIN_DIR/mtproxy"
chmod +x "$BIN_DIR/mtproxy"
add_to_profile "$BIN_DIR" "mtproxy" || true

log ""
log "$CHECK All set!"
log "  binary:  $SCRIPT_DIR/mtproxy"
log "  wrapper: $BIN_DIR/mtproxy"
log ""

if [ "$PROFILE_CHANGED" = "1" ]; then
    log "$CHECK Done! Restart your terminal (or: source \"$(detect_profile)\") to pick up the new PATH."
    log "Then run 'mtproxy' from anywhere."
elif echo ":$PATH:" | grep -qF ":$BIN_DIR:"; then
    log "$CHECK Done! PATH is already active. Run 'mtproxy' from anywhere."
else
    log "$CHECK Done! PATH is already configured in $(detect_profile)."
    log "If 'mtproxy' is not found in the current shell, run:"
    log "  source \"$(detect_profile)\""
fi