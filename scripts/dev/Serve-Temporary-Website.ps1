# ============================================================
# Serve-Temporary-Website.ps1 - run the dashboard locally
#
# The pages load data.json / dictionary.json with fetch(), which browsers block
# on file:// URLs - the site has to be served over HTTP to work. This script
# serves the docs folder with Python's built-in web server and opens the
# site in your default browser.
#
#   Run:   .\scripts\dev\Serve-Temporary-Website.ps1     (from the repo root)
#   Stop:  Ctrl+C in this window
# ============================================================

$ErrorActionPreference = "Stop"
$port = 8000

# Show the error in red and STAY OPEN until you close it, so a failure is always
# readable instead of the console vanishing. (The SUCCESS path doesn't use this -
# a running server keeps the window open by itself until you press Ctrl+C.)
function Hold-OnError([string]$msg) {
    Write-Host ""
    Write-Host $msg -ForegroundColor Red
    Write-Host ""
    Read-Host "FAILED - press Enter to close"
}

try {
    # ---- robust docs\ path ($PSScriptRoot is empty in some launch methods) ----
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir) -and $PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
    $docs = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "docs"

    if (-not (Test-Path -LiteralPath $docs)) {
        Hold-OnError "docs folder not found at: $docs`nRun this from inside the repo's scripts\dev\ folder."
        return
    }

    # ---- find Python ----
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $python) {
        Hold-OnError "Python was not found on PATH - install it from python.org first."
        return
    }

    # ---- make sure the port is free BEFORE we start (checking here lets us give
    #      a clear reason; doing it after would clash with the normal Ctrl+C stop).
    #      The persistent background site runs on a DIFFERENT port (8010), so a
    #      clash here is usually a leftover serve or another program. ----
    $inUse = $false
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        $listener.Start(); $listener.Stop()
    } catch { $inUse = $true }
    if ($inUse) {
        Hold-OnError "Port $port is already in use - another program (or a leftover serve) is using it.`nClose that or free port $port, then re-run this."
        return
    }

    Write-Host "Serving docs on http://localhost:$port  (Ctrl+C to stop)" -ForegroundColor Green
    Start-Process "http://localhost:$port/index.html"
    Set-Location -LiteralPath $docs
    # this blocks until you press Ctrl+C, which is the intended way to stop it
    & $python.Source -m http.server $port
}
catch {
    Hold-OnError ("Serve failed - {0}" -f $_.Exception.Message)
}
