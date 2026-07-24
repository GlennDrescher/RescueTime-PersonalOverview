# ============================================================
# RescueTime data fetcher (local wrapper)
#
# All fetch logic lives in scripts\fetch-addition.py — the SAME script
# the GitHub Action runs, so local and Action output can never drift.
#
#   1. Put your API key in Secrets.ini next to this script (key=...)
#      - the ini is gitignored so the key is never committed
#   2. Run from the repo root:  .\Fetch-Data.ps1
#   3. View the site with .\Serve-Website.ps1
#
# What it does:
#   - keeps docs\archive.json: your FULL per-day app history. Old days never
#     change, so they are downloaded once and kept. Each run only re-fetches
#     the last 3 days + the hourly rows, then rebuilds docs\data.json.
#   - first run (no archive.json yet) backfills the whole history.
#
# After upgrading to premium, pull the complete history once with:
#   .\Fetch-Data.ps1 -Rebuild
# ============================================================
param(
  [switch]$Rebuild,        # ignore the archive and backfill everything again
  [int]$RefreshDays = 3    # how many recent days (incl. today) to re-fetch
)

$ErrorActionPreference = "Stop"

# When run by double-clicking, the window closes the instant the script ends.
# So: on SUCCESS show a message and auto-close after 5 s; on FAILURE show the
# error and wait for a key press so you can actually read it.
function Fail([string]$msg) {
  Write-Host ""
  Write-Host $msg -ForegroundColor Red
  Write-Host ""
  Read-Host "Fetch FAILED - press Enter to close"
  exit 1
}

# Find a Python (Serve-Website.ps1 already relies on one being installed)
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { Fail "Python not found on PATH - install it first." }

$script = Join-Path $PSScriptRoot "scripts\fetch-addition.py"
$pyArgs = @($script, "--refresh-days", $RefreshDays)
if ($Rebuild) { $pyArgs += "--rebuild" }

try {
  & $py.Source @pyArgs
  $code = $LASTEXITCODE
} catch {
  Fail "Fetch failed - $($_.Exception.Message)"
}
if ($code -ne 0) { Fail "Fetch failed (exit $code) - see the messages above." }

Write-Host ""
Write-Host "Fetch succeeded." -ForegroundColor Green
Write-Host "View:  .\Serve-Website.ps1  ->  http://localhost:8000/index.html" -ForegroundColor Green
Write-Host ""
Write-Host "Closing in 5 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 5
