# mtproxy-checker

A small Go utility that checks which MTProto proxies in a list actually work.
It performs a real MTProto handshake (`help.getNearestDC`) through each proxy
using [gotd/td](https://github.com/gotd/td), so a proxy is reported as working
only if it can relay a real Telegram request.

## Features

- Real MTProto handshake, not just a TCP port check
- Parallel checks (30 workers by default)
- Live progress line: `Checked / Working / Remaining`
- Hard per-proxy timeout - the tool cannot hang
- Clean output: `Working proxies:` followed by the list
- Results saved to your XDG Downloads directory
  (`xdg-user-dir DOWNLOAD`, with `~/Downloads` as fallback)

## Requirements

- Go 1.25 or newer
- `curl`
- `xdg-user-dir` (part of `xdg-user-dirs`, pre-installed on most desktops)
- Linux or macOS

On Ubuntu / Debian:

```bash
sudo apt install -y golang-go curl xdg-user-dirs
```

If your distro ships an older Go, install 1.25+ from https://go.dev/dl/.

## Installation

```bash
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git ~/mtproxy-checker
cd ~/mtproxy-checker
./install.sh
```

The installer:

1. downloads dependencies (`go mod tidy`),
2. builds the binary at `~/mtproxy-checker/mtproxy`,
3. copies `mtproxy.sh` into `~/.local/bin/` as `mtproxy`.

Make sure `~/.local/bin` is in your `PATH` (it is by default on Ubuntu):

```bash
echo $PATH | tr ':' '\n' | grep -q "$HOME/.local/bin" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### Manual installation

```bash
cd ~/mtproxy-checker
go mod tidy
go build -o mtproxy .
mkdir -p ~/.local/bin
cp mtproxy.sh ~/.local/bin/mtproxy
chmod +x ~/.local/bin/mtproxy
```

## Usage

```bash
mtproxy
```

What happens:

1. `mtproxy` command downloads a fresh proxy list from
   [SoliSpirit/mtproto](https://github.com/SoliSpirit/mtproto) into your
   Downloads folder (detected via `xdg-user-dir DOWNLOAD`, fallback
   `~/Downloads`).
2. The `mtproxy` binary reads that file, checks every proxy in parallel,
   and writes working ones to `available_proxies.txt` in the same folder.
3. The working list is printed to stdout.

## Configuration

All settings live in `main.go`:

```go
const (
    workers = 30               // parallel checks
    timeout = 10 * time.Second // hard upper bound per check
)
```

File paths are resolved at runtime via `xdg-user-dir DOWNLOAD`
(and `$HOME/Downloads` as fallback), so the tool works for any user,
locale, or custom XDG setup without code changes.

## Output

Progress line (stderr, single line, updates in place):

```
⠼ Checked: 313/315 | Working: 5 | Remaining: 2
```

Final output (stdout):

```
Working proxies:
https://t.me/proxy?server=...&port=...&secret=...
...
```

Capture only the list into a file:

```bash
mtproxy > working.txt
```

Silence the progress and download messages:

```bash
mtproxy 2>/dev/null
```

## Uninstall

The project ships with `uninstall.sh`, which reverses what `install.sh` did.

### Standard uninstall

Run from anywhere - the script finds its own directory:

```bash
~/mtproxy-checker/uninstall.sh
```

Removes:

- `~/.local/bin/mtproxy` (the wrapper)
- `~/mtproxy-checker/mtproxy` (the compiled binary)
- `all_proxies.txt` and `available_proxies.txt` in your Downloads directory

The source repository (`~/mtproxy-checker`) is **kept** - you can rebuild
and reinstall any time with `./install.sh`.

### Full uninstall

To also delete the whole project directory:

```bash
~/mtproxy-checker/uninstall.sh --purge
```

For safety the script refuses to delete `$HOME` or `/` even if invoked
from a broken location.

### Help

```bash
~/mtproxy-checker/uninstall.sh --help
```

## How it works

For each proxy, `mtproxy-checker`:

1. parses `server`, `port`, and `secret` from the `t.me/proxy` URL
   (hex, base64url, and base64 secrets are supported),
2. builds an MTProxy resolver via `dcs.MTProxy`,
3. connects using `gotd/td` with the public test credentials
   (`telegram.TestAppID` / `telegram.TestAppHash`),
4. calls `help.getNearestDC` - this method does not require authorization,
   but it does require a fully working MTProto tunnel,
5. marks the proxy as working only if the call succeeds.

Any failure - timeout, invalid secret, connection refused, RPC error -
counts as "not working".

## License

MIT