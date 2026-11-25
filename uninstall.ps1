param(
    [switch]$Purge
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir    = Join-Path $env:USERPROFILE "bin"
$Installed = Join-Path $BinDir "mtproxy.exe"
$Leftovers = @(
    (Join-Path $BinDir "mtproxy.ps1"),
    (Join-Path $ScriptDir "mtproxy.exe")
)

$ok = "[OK]"; $warn = "[!]"; $bin = "-"
try {
    if ([Console]::OutputEncoding.WebName -match 'utf-?8') { $ok = "✅"; $warn = "⚠️"; $bin = "🗑" }
} catch {}

function Find-Go {
    $cmd = Get-Command go -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $env:USERPROFILE "go-sdk\bin\go.exe"
    if (Test-Path $local) { return $local }
    return $null
}

$cleaned = $false

if (Test-Path $Installed) {
    & $Installed --clean
    if ($LASTEXITCODE -eq 0) { $cleaned = $true }
}

if (-not $cleaned) {
    $go = Find-Go
    if ($go -and (Test-Path (Join-Path $ScriptDir "go.mod"))) {
        Write-Host "Building a temporary copy of mtproxy to find the proxy lists..." -ForegroundColor Gray
        Push-Location $ScriptDir
        try {
            & $go run . --clean
            if ($LASTEXITCODE -eq 0) { $cleaned = $true }
        } finally {
            Pop-Location
        }
    }
}

if (-not $cleaned) {
    Write-Host "$warn Couldn't locate the proxy lists automatically." -ForegroundColor Yellow
    Write-Host "   If you still have them, delete them from your Downloads folder by hand." -ForegroundColor Yellow
}

foreach ($f in @($Installed) + $Leftovers) {
    if (Test-Path $f) {
        Remove-Item -Force $f
        Write-Host "$bin Removed $f" -ForegroundColor Yellow
    }
}

if ($Purge) {
    $root = [IO.Path]::GetPathRoot($ScriptDir)
    if ($ScriptDir -eq $env:USERPROFILE -or $ScriptDir.TrimEnd('\') -eq $root.TrimEnd('\')) {
        Write-Host "$warn Refusing to delete $ScriptDir" -ForegroundColor Red
        exit 1
    }
    Set-Location $root
    Remove-Item -Recurse -Force $ScriptDir
    Write-Host "$bin Removed $ScriptDir" -ForegroundColor Yellow
}

Write-Host "$ok Uninstall complete. Thanks for using mtproxy-checker!" -ForegroundColor Green