# mtproxy-checker

A small Go utility that checks which MTProto proxies in a list actually work. It performs a real MTProto handshake (`help.getNearestDC`) through each proxy using [gotd/td](https://github.com/gotd/td), so a proxy is reported as working only if it can relay a real Telegram request.

## Features

- Real MTProto handshake, not just a TCP port check
- Parallel checks (30 workers by default)
- Clean output: `Working proxies:` followed by the list
- Results saved to your Downloads folder
- Works on **Linux**, **macOS** and **Windows**

## Requirements

- **Go 1.25 or newer**
- **curl** - used by the Unix wrapper to download the proxy list (pre-installed on most systems)

On Ubuntu / Debian:

```bash
sudo apt install -y golang-go curl
```

If your distro ships an older Go, install 1.25+ from [https://go.dev/dl/](https://go.dev/dl/).

## Installation

### Linux / macOS

```bash
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git ~/mtproxy-checker
cd ~/mtproxy-checker
./install.sh
```

Make sure `~/.local/bin` is in your `PATH` (it is by default on Ubuntu):

```bash
echo $PATH | tr ':' '\n' | grep -q "$HOME/.local/bin" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

#### Manual installation (Unix)

```bash
cd ~/mtproxy-checker
go mod tidy
go build -o mtproxy .
mkdir -p ~/.local/bin
cp mtproxy.sh ~/.local/bin/mtproxy
chmod +x ~/.local/bin/mtproxy
```

### Windows

Open **PowerShell** (no administrator rights required) and run:

```powershell
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git "$env:USERPROFILE\mtproxy-checker"
cd "$env:USERPROFILE\mtproxy-checker"
.\install.ps1
```

#### Manual installation (Windows)

```powershell
cd "$env:USERPROFILE\mtproxy-checker"
go mod tidy
go build -o mtproxy.exe .
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\bin" | Out-Null
Copy-Item .\mtproxy.ps1 "$env:USERPROFILE\bin\mtproxy.ps1"
```

## Usage

### Linux / macOS

```bash
mtproxy
```

### Windows

```powershell
mtproxy
```

> If PowerShell cannot find `mtproxy`, either restart the terminal (to reload `PATH`) or run the wrapper directly:  
> `& "$env:USERPROFILE\bin\mtproxy.ps1"`

What happens on any platform:

1. The wrapper downloads a fresh proxy list from [SoliSpirit/mtproto](https://github.com/SoliSpirit/mtproto) into your **Downloads** folder.
2. The native binary (`mtproxy` or `mtproxy.exe`) reads that file, checks every proxy in parallel, and writes working ones to `available_proxies.txt` in the same folder.
3. The working list is printed to `stdout`.

## Configuration

All settings live in `main.go`:

```go
const (
    workers = 30               // parallel checks
    timeout = 10 * time.Second // hard upper bound per check
)
```

## Output

Progress line (`stderr`):

```text
⠼ Checked: 313/315 | Working: 5 | Remaining: 2
```

Final output (`stdout`):

```text
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

### Linux / macOS

The project ships with `uninstall.sh`, which reverses what `install.sh` did.

Standard uninstall:

```bash
~/mtproxy-checker/uninstall.sh
```

Removes:

- `~/.local/bin/mtproxy` (the wrapper)
- `~/mtproxy-checker/mtproxy` (the compiled binary)
- `all_proxies.txt` and `available_proxies.txt` in your Downloads directory

The source repository (`~/mtproxy-checker`) is kept - you can rebuild and reinstall any time with `./install.sh`.

Full uninstall (also deletes the whole project directory):

```bash
~/mtproxy-checker/uninstall.sh --purge
```

Help:

```bash
~/mtproxy-checker/uninstall.sh --help
```

### Windows

Run **PowerShell**:

```powershell
cd "$env:USERPROFILE\mtproxy-checker"
.\uninstall.ps1
```

Removes:

- `%USERPROFILE%\bin\mtproxy.ps1` (the wrapper)
- `%USERPROFILE%\mtproxy-checker\mtproxy.exe` (the compiled binary)
- `all_proxies.txt` and `available_proxies.txt` in your Downloads folder

Full uninstall (also deletes the project directory):

```powershell
.\uninstall.ps1 -Purge
```

## How it works

For each proxy, `mtproxy-checker`:

- parses `server`, `port`, and `secret` from the `t.me/proxy` URL (hex, base64url, and base64 secrets are supported),
- builds an MTProxy resolver via `dcs.MTProxy`,
- connects using `gotd/td` with the public test credentials (`telegram.TestAppID` / `telegram.TestAppHash`),
- calls `help.getNearestDC` - this method does **not** require authorization, but it does require a fully working MTProto tunnel,
- marks the proxy as working only if the call succeeds. Any failure - timeout, invalid secret, connection refused, RPC error - counts as “not working”.

## License

MIT
