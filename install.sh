#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LOCAL_GO_DIR="$HOME/.local/go"
REQUIRED_GO="1.27"
FALLBACK_GO_VERSION="1.27.0"
PROFILE_CHANGED=0

if have locale; then
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
if [ "$SUPPORTS_UTF8" = "1" ] && [ "${TERM:-}" != "linux" ]; then
    CHECK="✅"; CROSS="❌"; GEAR="🔧"; PARTY="🎉"
else
    CHECK="[OK]"; CROSS="[ERR]"; GEAR="*"; PARTY="[OK]"
fi

log()  { echo "[install] $*" >&2; }
die()  { echo "[install] $CROSS $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

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
        *)       die "Sorry, $(uname -s) isn't supported. Supported systems: Linux, macOS, Windows." ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             die "Sorry, the $(uname -m) architecture isn't supported (need x86_64 or arm64)." ;;
    esac
}

ensure_downloader() {
    if have curl; then
        log "$CHECK curl: found"
        return 0
    fi
    if have wget; then
        log "$CHECK wget: found"
        return 0
    fi

    log "$GEAR Neither curl nor wget found; attempting to install curl..."

    local pm=""
    if have apt-get; then
        pm="apt-get"
    elif have dnf; then
        pm="dnf"
    elif have yum; then
        pm="yum"
    elif have pacman; then
        pm="pacman"
    elif have apk; then
        pm="apk"
    elif have brew; then
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

    if ! have curl; then
        die "curl installation failed. Please install curl or wget manually."
    fi
    log "$CHECK curl: installed"
}

fetch_text() {
    if have curl; then
        curl -fsSL --max-time 15 "$1"
    elif have wget; then
        wget -q -T 15 -O - "$1"
    else
        return 1
    fi
}

download_file() {
    local url="$1" out="$2"
    if have curl; then
        curl -fsSL --retry 3 -o "$out" "$url"
    elif have wget; then
        wget -q -O "$out" "$url"
    else
        return 1
    fi
}

latest_go_version() {
    local v
    v="$(fetch_text "https://go.dev/VERSION?m=text" 2>/dev/null | head -n 1 | sed 's/^go//' || true)"
    if printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
        echo "$v"
    else
        echo "$FALLBACK_GO_VERSION"
    fi
}

go_version() {
    "$1" env GOVERSION 2>/dev/null | sed -e 's/^go//' -e 's/[[:space:]].*$//' || true
}

install_go() {
    local version tarball url tmp
    if [ -n "${GO_INSTALL_VERSION:-}" ]; then
        version="$GO_INSTALL_VERSION"
        if ! version_ge "$version" "$REQUIRED_GO"; then
            die "GO_INSTALL_VERSION=$version is too old - mtproxy needs Go ${REQUIRED_GO} or newer."
        fi
    else
        version="$(latest_go_version)"
    fi

    tarball="go${version}.${OS}-${ARCH}.tar.gz"
    url="https://go.dev/dl/${tarball}"
    log "$GEAR Downloading Go $version (around 70 MB, this may take a minute)..."

    tmp="$(mktemp -d)"
    if ! download_file "$url" "$tmp/$tarball"; then
        rm -rf "$tmp"
        die "Couldn't download $url - check your internet connection and try again."
    fi
    if ! tar -C "$tmp" -xzf "$tmp/$tarball"; then
        rm -rf "$tmp"
        die "Couldn't unpack $tarball - the download may be corrupted, please try again."
    fi
    if [ ! -d "$tmp/go" ]; then
        rm -rf "$tmp"
        die "Unexpected archive layout in $tarball."
    fi

    mkdir -p "$(dirname "$LOCAL_GO_DIR")"
    rm -rf "$LOCAL_GO_DIR"
    mv "$tmp/go" "$LOCAL_GO_DIR"
    rm -rf "$tmp"

    export PATH="$LOCAL_GO_DIR/bin:$PATH"
    GO_VER="$(go_version "$LOCAL_GO_DIR/bin/go")"
    if [ -z "$GO_VER" ] || ! version_ge "$GO_VER" "$REQUIRED_GO"; then
        die "Go install failed: got ${GO_VER:-unknown}, need ${REQUIRED_GO}+."
    fi
    log "$CHECK Go $GO_VER installed to $LOCAL_GO_DIR"
}

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
        log "$CHECK $label: $dir is already on your PATH (in $profile)"
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
    log "$CHECK $label: added $dir to your PATH (in $profile)"
    return 0
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

ensure_downloader

log "$GEAR Setting up mtproxy-checker..."

GO_OK=0
if have go; then
    GO_VER="$(go_version go)"
    if [ -n "$GO_VER" ] && version_ge "$GO_VER" "$REQUIRED_GO"; then
        GO_OK=1
        log "$CHECK Go $GO_VER found - using it"
    elif [ -n "$GO_VER" ]; then
        log "$GEAR Found Go $GO_VER, but ${REQUIRED_GO}+ is needed"
    fi
fi

if [ "$GO_OK" = "0" ] && [ -x "$LOCAL_GO_DIR/bin/go" ]; then
    GO_VER="$(go_version "$LOCAL_GO_DIR/bin/go")"
    if [ -n "$GO_VER" ] && version_ge "$GO_VER" "$REQUIRED_GO"; then
        export PATH="$LOCAL_GO_DIR/bin:$PATH"
        GO_OK=1
        log "$CHECK Go $GO_VER found in $LOCAL_GO_DIR - using it"
    fi
fi

if [ "$GO_OK" = "0" ]; then
    install_go
fi

if [ -x "$LOCAL_GO_DIR/bin/go" ]; then
    case "$(command -v go || true)" in
        "$LOCAL_GO_DIR/bin/go") add_to_profile "$LOCAL_GO_DIR/bin" "go" || true ;;
    esac
fi

cd "$SCRIPT_DIR"
log "$GEAR Fetching dependencies..."
if ! go mod tidy; then
    die "Couldn't fetch dependencies - check your internet connection and try again."
fi

mkdir -p "$BIN_DIR"
log "$GEAR Building mtproxy..."
if ! go build -trimpath -ldflags "-s -w" -o "$BIN_DIR/mtproxy" .; then
    die "Build failed - see the errors above."
fi
chmod +x "$BIN_DIR/mtproxy"

if [ -f "$SCRIPT_DIR/mtproxy" ]; then
    rm -f -- "$SCRIPT_DIR/mtproxy"
    log "$GEAR Removed an old binary from the project folder (no longer needed)"
fi

add_to_profile "$BIN_DIR" "mtproxy" || true

log ""
log "$PARTY All set! mtproxy is installed at $BIN_DIR/mtproxy"
log ""

if [ "$PROFILE_CHANGED" = "1" ]; then
    log "$CHECK Restart your terminal (or run: source \"$(detect_profile)\"),"
    log "   then type 'mtproxy' from any folder."
elif echo ":$PATH:" | grep -qF ":$BIN_DIR:"; then
    log "$CHECK Just type 'mtproxy' from any folder."
else
    log "$CHECK PATH is already configured in $(detect_profile)."
    log "   If 'mtproxy' isn't found in this terminal, run: source \"$(detect_profile)\""
fi