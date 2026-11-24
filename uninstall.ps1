# uninstall.ps1
param(
    [switch]$Purge
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $env:USERPROFILE "bin"
$Wrapper = Join-Path $BinDir "mtproxy.ps1"
$Binary = Join-Path $ScriptDir "mtproxy.exe"
$Downloads = [Environment]::GetFolderPath("UserProfile") + "\Downloads"

$removed = 0

foreach ($f in @($Wrapper, $Binary,
    (Join-Path $Downloads "all_proxies.txt"),
    (Join-Path $Downloads "available_proxies.txt"))) {
    if (Test-Path $f) {
        Remove-Item -Force $f
        Write-Host "Removed: $f" -ForegroundColor Yellow
        $removed++
    }
}

if ($Purge) {
    if ($ScriptDir -eq $env:USERPROFILE -or $ScriptDir -eq "C:\") {
        Write-Error "Refusing to delete $ScriptDir"
        exit 1
    }
    Set-Location C:\
    Remove-Item -Recurse -Force $ScriptDir
    Write-Host "Removed: $ScriptDir" -ForegroundColor Yellow
    $removed++
}

if ($removed -eq 0) {
    Write-Host "Nothing to remove." -ForegroundColor Gray
} else {
    Write-Host "Uninstall complete." -ForegroundColor Green
}