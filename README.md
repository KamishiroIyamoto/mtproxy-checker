# mtproxy-checker

A small Go utility that checks which MTProto proxies in a list actually work. It performs a real MTProto handshake (`help.getNearestDC`) through each proxy using [gotd/td](https://github.com/gotd/td), so a proxy is reported as working only if it can relay a real Telegram request.

---

## Features

- Works on **Linux**, **macOS**, and **Windows**
- Real MTProto handshake, not just a TCP port check
- Two-stage pipeline: fast TCP pre-check (128 parallel) feeds a full MTProto check (64 parallel)
- Fail-fast: a proxy that drops the connection is rejected immediately instead of waiting for the timeout
- Duplicate proxies are detected and checked only once
- Working proxies are sorted by handshake latency, fastest first
- Ctrl+C stops the run and still saves everything found so far

---

## Installation

The installer is idempotent: it checks what's already on the system and installs only what's missing.

### Option A - no git: download the ZIP

1. Download from **_[URL](https://github.com/KamishiroIyamoto/mtproxy-checker/archive/refs/heads/main.zip)_** or open the **_[repository page](https://github.com/KamishiroIyamoto/mtproxy-checker)_** → Green button **Code** → **Download ZIP**.
2. Extract the archive anywhere you like.
3. Open a terminal in the extracted folder. Then:

**Linux / macOS**

```bash
./install.sh
```

**Windows** (PowerShell - right-click the Start button → "Windows PowerShell" or "Terminal")

```powershell
.\install.ps1
```

> If PowerShell says running scripts is disabled, run it like this instead:
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\install.ps1
> ```

After installation, **restart your terminal**.

### Option B - with git

**Linux / macOS**

```bash
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git
cd mtproxy-checker
./install.sh
```

**Windows** (PowerShell)

```powershell
git clone https://github.com/KamishiroIyamoto/mtproxy-checker.git "$env:USERPROFILE\mtproxy-checker"
cd "$env:USERPROFILE\mtproxy-checker"
.\install.ps1
```

After installation, **restart your terminal**.

### What the installer does

**Linux / macOS:**

- Detects an existing Go ≥ 1.27 in `PATH` and uses it;
- Otherwise, if a previous run already installed Go to `~/.local/go`, reuses it;
- Otherwise, downloads the latest stable Go release from [go.dev](https://go.dev/dl/) into `~/.local/go` (falls back to 1.27.0 if go.dev can't be queried) and adds it to your `PATH` via the appropriate shell profile;
- Builds the program straight into `~/.local/bin/mtproxy`;
- Adds `~/.local/bin` to your `PATH` by appending an `export PATH=...` line to your shell profile (detected from `$SHELL`);
- Removes leftovers from older versions.

**Windows:**

- Detects an existing Go ≥ 1.27 in `PATH` and uses it;
- Otherwise, if a previous run already installed Go to `%USERPROFILE%\go-sdk`, reuses it;
- Otherwise, downloads the latest stable Go `.zip` from [go.dev](https://go.dev/dl/), extracts it to `%USERPROFILE%\go-sdk`, and adds it to your **user** `PATH`;
- Builds the program straight into `%USERPROFILE%\bin\mtproxy.exe`;
- Adds `%USERPROFILE%\bin` to your user `PATH`;
- Removes leftovers from older versions (e.g. the old `mtproxy.ps1` wrapper).

---

## Usage

```
mtproxy
```

What happens:

1. `mtproxy` downloads a fresh proxy list from [SoliSpirit/mtproto](https://github.com/SoliSpirit/mtproto) into your **Downloads** folder as `all_proxies.txt`. If the download fails but a previous copy exists, that copy is used and you're told how old it is.
2. Duplicates are removed.
3. Every proxy gets a quick TCP check; reachable ones are immediately passed on to the full MTProto check, so both stages run concurrently.
4. Working proxies are sorted by latency and written to `working_proxies.txt` in the same folder.
5. The sorted list is printed to `stdout`.

Press **Ctrl+C** at any time to stop - proxies confirmed so far are still saved. Press it a second time to quit immediately.

Other commands:

```
mtproxy --clean   # delete the downloaded and generated proxy lists
mtproxy --help    # show help, including where the files are stored
```

---

## Output

Messages and progress go to `stderr`; `stdout` contains **only** the proxy URLs.

```text
📥 Downloading a fresh proxy list...
📋 Got 389 proxies to check (skipped 11 duplicates)
🔎 Checking them now - this usually takes under a minute. Press Ctrl+C to stop early.
⠼ Reachable: 312/389 (98 open) | Handshake: 71/98 | Working: 12 | 9s
🎉 Done in 17.4s: 15 working proxies out of 389!
⚡ Fastest one answered in 182ms
💾 Saved to /home/user/Downloads/working_proxies.txt

✅ Working proxies, fastest first:
https://t.me/proxy?server=...&port=...&secret=...
...
```

Save only the list to a file:

```bash
mtproxy > working.txt
```

Hide all messages and progress:

```bash
mtproxy 2>/dev/null
```

---

## Configuration

All settings live in `config.go`:

```go
const (
    proxyListURL    = "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt"
    inputFileName   = "all_proxies.txt"       // downloaded list
    outputFileName  = "working_proxies.txt" // working proxies, fastest first
    dataDir         = ""                      // "" = Downloads folder; "~/mtproxy" also works
    defaultDirName  = "Downloads"             // fallback when the OS reports no Downloads folder
    downloadTimeout = 60 * time.Second

    tcpWorkers = 128             // stage 1: parallel TCP pre-checks
    tcpTimeout = 3 * time.Second // per TCP connect (including DNS)

    mtprotoWorkers  = 64               // stage 2: parallel MTProto handshakes
    mtprotoTimeout  = 10 * time.Second // hard upper bound per handshake
    mtprotoAttempts = 1                // connection attempts before a proxy is rejected
)
```

Changing any of these requires rebuilding - just re-run the installer.

> **File descriptor limits.** At peak the checker holds about `tcpWorkers + mtprotoWorkers` sockets. The defaults (~200) fit under macOS's default soft limit of 256. If you raise them on macOS, also raise the limit first: `ulimit -n 4096`.

If your network is flaky and you see fewer working proxies than expected, try `mtprotoAttempts = 2` or a longer `tcpTimeout`.

---

## Uninstall

### Linux / macOS

Run `uninstall.sh` **from the project folder**:

```bash
cd /path/to/mtproxy-checker    # wherever your project folder is
./uninstall.sh
```

Removes:

- `~/.local/bin/mtproxy` (the installed program)
- the downloaded and generated proxy lists - wherever `config.go` points, under whatever names it uses
- leftovers from older versions

The project folder itself is kept - you can reinstall any time with `./install.sh`.

Full uninstall (also deletes the project directory):

```bash
./uninstall.sh --purge
```

> **Note:** `uninstall.sh` does **not** remove the `PATH` entries that `install.sh` added to your shell profile (or the local Go install at `~/.local/go`). To undo those, edit the profile (`~/.bashrc`, `~/.zshrc`, etc.) and delete the blocks beginning with `# Added by mtproxy-checker installer`, and remove `~/.local/go` if you no longer need it.

Help:

```bash
./uninstall.sh --help
```

### Windows

Run **PowerShell** from the project folder:

```powershell
cd C:\path\to\mtproxy-checker    # wherever your project folder is
.\uninstall.ps1
```

Removes:

- `%USERPROFILE%\bin\mtproxy.exe` (the installed program)
- the downloaded and generated proxy lists - wherever `config.go` points, under whatever names it uses
- leftovers from older versions

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

---

## How it works

1. **Parsing.** `server`, `port`, and `secret` are extracted from each `t.me/proxy` URL (hex, base64url, and base64 secrets are supported). Entries with the same `host:port` and secret are checked once.
2. **Stage 1 - TCP.** A plain TCP connect with a short timeout. Closed ports fail instantly, dead hosts within `tcpTimeout`. Most of a typical list is filtered out here, cheaply.
3. **Stage 2 - MTProto.** For each reachable proxy, an MTProxy resolver is built via `dcs.MTProxy`, and `gotd/td` connects with the public test credentials (`telegram.TestAppID` / `telegram.TestAppHash`) and calls `help.getNearestDC`. This method does **not** require authorization, but it does require a fully working MTProto tunnel.
4. **Fail-fast.** gotd normally reconnects with backoff after a failure, which would burn the whole timeout on a broken proxy. A thin resolver wrapper counts connection attempts and aborts the check as soon as a reconnect is attempted.
5. **Ranking.** Time to a successful `help.getNearestDC` is recorded, and results are sorted fastest first.

Any failure - timeout, invalid secret, connection refused, RPC error - counts as "not working".

---

## License

MIT