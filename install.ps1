$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$ScriptDir         = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir            = Join-Path $env:USERPROFILE "bin"
$LocalGoDir        = Join-Path $env:USERPROFILE "go-sdk"
$RequiredGo        = [version]"1.27"
$FallbackGoVersion = "1.27.0"

$script:PathChanged = $false
$check = "[OK]"; $cross = "[ERR]"; $gear = "*"; $party = "[OK]"
try {
    if ([Console]::OutputEncoding.WebName -match 'utf-?8') {
        $check = "✅"; $cross = "❌"; $gear = "🔧"; $party = "🎉"
    }
} catch {}

function Log($msg)  { Write-Host "[install] $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[install] $cross $msg" -ForegroundColor Red; exit 1 }

function Get-GoVersion {
    try {
        $cmd = Get-Command go -ErrorAction SilentlyContinue
        if (-not $cmd) { return $null }
        $out = & $cmd.Source env GOVERSION 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $line = ($out | Select-Object -First 1)
        return (($line -replace '^go', '') -replace '\s.*$', '')
    } catch { return $null }
}

function Test-GoVersionOk {
    $v = Get-GoVersion
    if (-not $v) { return $false }
    try { return ([version]$v -ge $RequiredGo) } catch { return $false }
}

function Get-LatestGoVersion {
    try {
        $resp = Invoke-WebRequest -Uri "https://go.dev/VERSION?m=text" -UseBasicParsing -TimeoutSec 15
        $text = $resp.Content
        if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
        $first = (($text -split "`n")[0].Trim()) -replace '^go', ''
        if ($first -match '^\d+\.\d+(\.\d+)?$') { return $first }
    } catch {}
    return $FallbackGoVersion
}

function Add-ToUserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    if ($parts -contains $dir) {
        Log "$check $dir is already on your PATH"
        return
    }
    $newPath = if ($userPath) { "$userPath;$dir" } else { $dir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $script:PathChanged = $true
    Log "$check Added $dir to your PATH"
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

    $envArch = $env:PROCESSOR_ARCHITEW6432
    if (-not $envArch) { $envArch = $env:PROCESSOR_ARCHITECTURE }
    switch ($envArch) {
        'AMD64' { return "amd64" }
        'ARM64' { return "arm64" }
        'x86'   { return "386" }
        default { Fail "Sorry, the $envArch architecture isn't supported." }
    }
}

function Install-Go {
    if ($env:GO_INSTALL_VERSION) {
        $version = $env:GO_INSTALL_VERSION
        try {
            if ([version]$version -lt $RequiredGo) {
                Fail "GO_INSTALL_VERSION=$version is too old - mtproxy needs Go $RequiredGo or newer."
            }
        } catch {
            Fail "GO_INSTALL_VERSION=$version doesn't look like a valid version (expected something like 1.27.0)."
        }
    } else {
        $version = Get-LatestGoVersion
    }

    $arch    = Get-WindowsArch
    $zipName = "go$version.windows-$arch.zip"
    $url     = "https://go.dev/dl/$zipName"
    $tmp     = Join-Path $env:TEMP ("go-dl-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    try {
        Log "$gear Downloading Go $version (around 70 MB, this may take a minute)..."
        $zipPath = Join-Path $tmp $zipName
        try {
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        } catch {
            Fail "Couldn't download $url - check your internet connection and try again."
        }

        Log "$gear Unpacking to $LocalGoDir..."
        Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
        $extractedGo = Join-Path $tmp "go"
        if (-not (Test-Path $extractedGo)) { Fail "Unexpected archive layout in $zipName." }

        if (Test-Path $LocalGoDir) { Remove-Item -Recurse -Force $LocalGoDir }
        Move-Item $extractedGo $LocalGoDir
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    $env:Path = "$LocalGoDir\bin;$env:Path"
    Add-ToUserPath "$LocalGoDir\bin"
}

Log "$gear Setting up mtproxy-checker..."

$existing = Get-GoVersion
if ($existing -and (Test-GoVersionOk)) {
    Log "$check Go $existing found - using it"
} else {
    if ($existing) { Log "$cross Found Go $existing, but $RequiredGo+ is needed" }

    if (Test-Path (Join-Path $LocalGoDir "bin\go.exe")) {
        $env:Path = "$LocalGoDir\bin;$env:Path"
    }

    if (Test-GoVersionOk) {
        Log "$check Go $(Get-GoVersion) found in $LocalGoDir - using it"
    } else {
        Install-Go
        if (-not (Test-GoVersionOk)) { Fail "Go install failed - please try again." }
        Log "$check Go $(Get-GoVersion) installed to $LocalGoDir"
    }
}

Set-Location $ScriptDir
Log "$gear Fetching dependencies..."
& go mod tidy
if ($LASTEXITCODE -ne 0) { Fail "Couldn't fetch dependencies - check your internet connection and try again." }

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Log "$gear Building mtproxy..."
& go build -trimpath -ldflags "-s -w" -o "$BinDir\mtproxy.exe" .
if ($LASTEXITCODE -ne 0) { Fail "Build failed - see the errors above." }

foreach ($legacy in @((Join-Path $BinDir "mtproxy.ps1"), (Join-Path $ScriptDir "mtproxy.exe"))) {
    if (Test-Path $legacy) {
        Remove-Item -Force $legacy
        Log "$gear Removed a leftover from an older version: $legacy"
    }
}

Add-ToUserPath $BinDir

Log ""
Log "$party All set! mtproxy is installed at $BinDir\mtproxy.exe"
Log ""

if ($script:PathChanged) {
    Log "$check Restart your terminal, then type 'mtproxy' from any folder."
} else {
    Log "$check Just type 'mtproxy' from any folder."
}