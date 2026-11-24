# install.ps1
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $env:USERPROFILE "bin"

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go not found. Install from https://go.dev/dl/"
    exit 1
}

$requiredGo = "1.25"
$goVer = (go env GOVERSION) -replace '^go', ''
if (-not ([version]$goVer -ge [version]$requiredGo)) {
    Write-Error "Go $requiredGo or newer required, found $goVer"
    exit 1
}

Set-Location $ScriptDir
Write-Host "Fetching dependencies..." -ForegroundColor Cyan
go mod tidy
Write-Host "Building mtproxy.exe..." -ForegroundColor Cyan
go build -o "$ScriptDir\mtproxy.exe" .

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item "$ScriptDir\mtproxy.ps1" "$BinDir\mtproxy.ps1" -Force

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$BinDir*") {
    $newPath = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added $BinDir to user PATH. Restart terminal for changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installed:"
Write-Host "  binary: $ScriptDir\mtproxy.exe"
Write-Host "  wrapper: $BinDir\mtproxy.ps1"
Write-Host ""
Write-Host "Run 'mtproxy' from anywhere." -ForegroundColor Green