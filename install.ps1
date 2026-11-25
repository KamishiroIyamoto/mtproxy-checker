# install.ps1
$ErrorActionPreference = "Stop"

$ScriptDir        = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir           = Join-Path $env:USERPROFILE "bin"
$LocalGoDir       = Join-Path $env:USERPROFILE "go-sdk"
$RequiredGo       = [version]"1.25"
$GoInstallVersion = if ($env:GO_INSTALL_VERSION) { $env:GO_INSTALL_VERSION } else { "1.25.0" }

$script:PathChanged = $false
$check = "[OK]"; $cross = "[ERR]"
try {
    if ([Console]::OutputEncoding.WebName -match 'utf-?8') { $check = "✅"; $cross = "❌" }
} catch {}

function Log($msg)  { Write-Host "[install] $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Error "[install] $cross $msg"; exit 1 }

function Get-GoVersion {
    try {
        $cmd = Get-Command go -ErrorAction SilentlyContinue
        if (-not $cmd) { return $null }
        $out = & $cmd.Source env GOVERSION 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($out -replace '^go', '')
    } catch { return $null }
}

function Test-GoVersionOk {
    $v = Get-GoVersion
    if (-not $v) { return $false }
    try { return ([version]$v -ge $RequiredGo) } catch { return $false }
}

function Add-ToUserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    if ($parts -contains $dir) {
        Log "PATH already contains $dir"
        return
    }
    $newPath = if ($userPath) { "$userPath;$dir" } else { $dir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $script:PathChanged = $true
    Log "Added $dir to user PATH"
}

function Get-WindowsArch {
    try {
        $rt = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        switch ($rt) {
            'X64'   { return "amd64" }
            'Arm64' { return "arm64" }
            'X86'   { return "386" }
        }
    } catch {}

    $envArch = $env:PROCESSOR_ARCHITECTURE
    if (-not $envArch) { $envArch = $env:PROCESSOR_ARCHITEW6432 }
    switch ($envArch) {
        'AMD64' { return "amd64" }
        'ARM64' { return "arm64" }
        'x86'   { return "386" }
        default { Fail "Unsupported architecture: $envArch" }
    }
}

function Install-Go {
    $arch = Get-WindowsArch
    $zipName = "go$GoInstallVersion.windows-$arch.zip"
    $url     = "https://go.dev/dl/$zipName"
    $tmp     = Join-Path $env:TEMP ("go-dl-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    try {
        Log "Downloading Go $GoInstallVersion from $url"
        $zipPath = Join-Path $tmp $zipName
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

        Log "Extracting to $LocalGoDir"
        Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
        $extractedGo = Join-Path $tmp "go"
        if (-not (Test-Path $extractedGo)) { Fail "Unexpected archive layout in $zipName" }

        if (Test-Path $LocalGoDir) { Remove-Item -Recurse -Force $LocalGoDir }
        Move-Item $extractedGo $LocalGoDir
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    $env:Path = "$LocalGoDir\bin;$env:Path"
    Add-ToUserPath "$LocalGoDir\bin"
}

if (-not (Test-GoVersionOk) -and (Test-Path (Join-Path $LocalGoDir "bin\go.exe"))) {
    $env:Path = "$LocalGoDir\bin;$env:Path"
}

if (-not (Test-GoVersionOk)) {
    Log "Go not found or too old, installing..."
    Install-Go
    if (-not (Test-GoVersionOk)) { Fail "Go install failed" }
}

Log "Using Go $(Get-GoVersion)"

Set-Location $ScriptDir
Log "Fetching dependencies (go mod tidy)..."
& go mod tidy
if ($LASTEXITCODE -ne 0) { Fail "go mod tidy failed" }

Log "Building mtproxy.exe..."
& go build -o "$ScriptDir\mtproxy.exe" .
if ($LASTEXITCODE -ne 0) { Fail "go build failed" }

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$wrapperContent = (Get-Content "$ScriptDir\mtproxy.ps1" -Raw).Replace('__MTPROXY_BIN__', "$ScriptDir\mtproxy.exe")
Set-Content -Path "$BinDir\mtproxy.ps1" -Value $wrapperContent -Encoding UTF8
Add-ToUserPath $BinDir

Log ""
Log "$check All set!"
Log "  binary:  $ScriptDir\mtproxy.exe"
Log "  wrapper: $BinDir\mtproxy.ps1"
Log ""

if ($script:PathChanged) {
    Log "$check Done! Restart your terminal to pick up the new PATH, then run 'mtproxy' from anywhere."
} else {
    Log "$check Done! '$BinDir' is already on your user PATH. Run 'mtproxy' from anywhere."
}