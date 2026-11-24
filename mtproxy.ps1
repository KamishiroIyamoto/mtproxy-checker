# mtproxy.ps1
$ErrorActionPreference = "Stop"

$Url = "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt"

$Downloads = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
if (-not (Test-Path $Downloads)) {
    New-Item -ItemType Directory -Force -Path $Downloads | Out-Null
}

$InputFile = Join-Path $Downloads "all_proxies.txt"
$BinPath = if ($env:MTPROXY_BIN) { $env:MTPROXY_BIN } else { Join-Path $PSScriptRoot "mtproxy.exe" }

Write-Host "Downloading proxy list from $Url" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $Url -OutFile $InputFile -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Error "Error: failed to download $Url"
    exit 1
}

if (-not (Test-Path $InputFile) -or (Get-Item $InputFile).Length -eq 0) {
    Write-Error "Error: downloaded file is empty"
    exit 1
}

if (-not (Test-Path $BinPath)) {
    Write-Error "Error: $BinPath not found."
    exit 1
}

& $BinPath