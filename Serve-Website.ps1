# ============================================================
# Serve-Website.ps1 - run the dashboard locally
#
# The pages load data.json / dictionary.json with fetch(), which browsers block
# on file:// URLs - the site has to be served over HTTP to work. This script
# serves the docs folder with Python's built-in web server and opens the
# site in your default browser.
#
#   Run:   .\Serve-Website.ps1        (from the repo root)
#   Stop:  Ctrl+C in this window
# ============================================================

$port = 8000

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) {
  Write-Host "Python was not found on PATH - install it from python.org first." -ForegroundColor Red
  exit 1
}

Write-Host "Serving docs on http://localhost:$port  (Ctrl+C to stop)" -ForegroundColor Green
Start-Process "http://localhost:$port/index.html"
Set-Location (Join-Path $PSScriptRoot "docs")
& $python.Source -m http.server $port
