# mtproxy-checker

A small Go utility that checks which MTProto proxies in a list actually work. It performs a real MTProto handshake (`help.getNearestDC`) through each proxy using [gotd/td](https://github.com/gotd/td), so a proxy is reported as working only if it can relay a real Telegram request.

## Features

- Real MTProto handshake, not just a TCP port check
- Parallel checks (30 workers by default)
- Clean output: `Working proxies:` followed by the list
- Results saved to your Downloads folder
- Works on **Linux**, **macOS**, and **Windows**

## Installation

The installer is self-contained: it checks what's already on the system and installs anything missing (Go 1.25+ if needed). No manual prerequisites.

### Linux / macOS

```bash
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git ~/mtproxy-checker
cd ~/mtproxy-checker
./install.sh
```

What the installer does:

- Ensures a downloader is available: if neither `curl` nor `wget` is present, it attempts to install `curl` via the system package manager (`apt-get`, `dnf`, `yum`, `pacman`, `apk`, or `brew`);
- Detects an existing Go ≥ 1.25 in `PATH` and uses it;
- Otherwise, if a previous run already installed Go to `~/.local/go`, reuses it;
- Otherwise, downloads the official Go tarball from [go.dev](https://go.dev/dl/) into `~/.local/go` and adds it to your `PATH` (via the appropriate shell profile);
- Builds the binary at `~/mtproxy-checker/mtproxy`;
- Copies `mtproxy.sh` into `~/.local/bin/` as `mtproxy`;
- Adds `~/.local/bin` to your `PATH` automatically by appending the proper `export PATH=...` line to your shell profile (detected from `$SHELL`).

The installer is idempotent: running it again will not create duplicate entries in your profile and will reuse the previously installed Go.

After installation, **restart your terminal** (or run `source <your-profile>`) so the new `PATH` takes effect. Then run:

```bash
mtproxy
```

To override the Go version that gets installed (for example, to pin to a newer release):

```bash
GO_INSTALL_VERSION=1.26.0 ./install.sh
```

### Windows

Open **PowerShell** (no administrator rights required) and run:

```powershell
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git "$env:USERPROFILE\mtproxy-checker"
cd "$env:USERPROFILE\mtproxy-checker"
.\install.ps1
```

What the installer does:

- Detects an existing Go ≥ 1.25 in `PATH` and uses it;
- Otherwise, if a previous run already installed Go to `%USERPROFILE%\go-sdk`, reuses it;
- Otherwise, downloads the official Go `.zip` from [go.dev](https://go.dev/dl/), extracts it to `%USERPROFILE%\go-sdk`, and adds it to your **user** `PATH`;
- Builds the binary at `mtproxy-checker\mtproxy.exe`;
- Copies `mtproxy.ps1` into `%USERPROFILE%\bin` as `mtproxy.ps1`;
- Adds `%USERPROFILE%\bin` to your user `PATH`.

The installer is idempotent.

After installation, **restart your terminal** so the updated `PATH` is picked up. Then run:

```powershell
mtproxy
```

To override the Go version that gets installed:

```powershell
$env:GO_INSTALL_VERSION = "1.26.0"; .\install.ps1
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

> If PowerShell cannot find `mtproxy` right after installation, restart the terminal so it reloads `PATH`. As a fallback you can run the wrapper directly:  
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

> **Note:** `uninstall.sh` does **not** remove the `PATH` entries that `install.sh` added to your shell profile (or the local Go install at `~/.local/go`). To undo those, edit the profile (`~/.bashrc`, `~/.zshrc`, etc.) and delete the blocks beginning with `# Added by mtproxy-checker installer`, and remove `~/.local/go` if you no longer need it.

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

> **Note:** `uninstall.ps1` does **not** remove `%USERPROFILE%\bin` or `%USERPROFILE%\go-sdk` from your user `PATH`. To clean those up manually:
> ```powershell
> $p = [Environment]::GetEnvironmentVariable("Path", "User")
> $new = ($p -split ';' | Where-Object {
>     $_ -and $_ -ne "$env:USERPROFILE\bin" -and $_ -ne "$env:USERPROFILE\go-sdk\bin"
> }) -join ';'
> [Environment]::SetEnvironmentVariable("Path", $new, "User")
> Remove-Item -Recurse -Force "$env:USERPROFILE\go-sdk" -ErrorAction SilentlyContinue
> ```

## How it works

For each proxy, `mtproxy-checker`:

- parses `server`, `port`, and `secret` from the `t.me/proxy` URL (hex, base64url, and base64 secrets are supported),
- builds an MTProxy resolver via `dcs.MTProxy`,
- connects using `gotd/td` with the public test credentials (`telegram.TestAppID` / `telegram.TestAppHash`),
- calls `help.getNearestDC` - this method does **not** require authorization, but it does require a fully working MTProto tunnel,
- marks the proxy as working only if the call succeeds. Any failure - timeout, invalid secret, connection refused, RPC error - counts as “not working”.

## License

MIT
