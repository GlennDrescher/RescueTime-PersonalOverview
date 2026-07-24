# ============================================================
# RescueTime data fetcher (local wrapper)
#
# All fetch logic lives in fetch-addition.py (next to this script) — the SAME
# script the GitHub Action runs, so local and Action output can never drift.
#
#   1. Put your API key in Secrets.ini in the REPO ROOT (key=...)
#      - the ini is gitignored so the key is never committed
#   2. Run from the repo root:  .\scripts\dev\Fetch-RescueTime-Data.ps1
#   3. View the site with  .\scripts\dev\Serve-Temporary-Website.ps1
#
# What it does:
#   - keeps docs\archive.json: your FULL per-day app history. Old days never
#     change, so they are downloaded once and kept. Each run only re-fetches
#     the last 3 days + the hourly rows, then rebuilds docs\data.json.
#   - first run (no archive.json yet) backfills the whole history.
#
# After upgrading to premium, pull the complete history once with:
#   .\scripts\dev\Fetch-RescueTime-Data.ps1 -Rebuild
# ============================================================
param(
  [switch]$Rebuild,        # ignore the archive and backfill everything again
  [int]$RefreshDays = 3    # how many recent days (incl. today) to re-fetch
)

$ErrorActionPreference = "Stop"

# When run by double-clicking, the window closes the instant the script ends.
# The run is wrapped so it ALWAYS reports its outcome: SUCCESS (green) auto-closes
# after 10 s; a FAILURE (red) stays on screen until you close it yourself.
$ok = $false
try {
  # Find a Python (the serve script already relies on one being installed)
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if (-not $py) { throw "Python not found on PATH - install it first." }

  # fetch-addition.py lives one level UP (in scripts\), since this wrapper is
  # in scripts\dev\. Resolve the script dir robustly, then go up one to reach it.
  $scriptDir = $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($scriptDir) -and $PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
  if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
  $script = Join-Path (Split-Path -Parent $scriptDir) "fetch-addition.py"
  $pyArgs = @($script, "--refresh-days", $RefreshDays)
  if ($Rebuild) { $pyArgs += "--rebuild" }

  & $py.Source @pyArgs
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Fetch failed (exit $code) - see the messages above." }

  Write-Host ""
  Write-Host "Fetch succeeded." -ForegroundColor Green
  Write-Host "View:  .\scripts\dev\Serve-Temporary-Website.ps1  ->  http://localhost:8000/index.html" -ForegroundColor Green
  $ok = $true
}
catch {
  Write-Host ""
  Write-Host "Fetch FAILED:" -ForegroundColor Red
  Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
  Write-Host ""
  if ($ok) {
    Write-Host "Closing in 10 seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
  } else {
    # a failure stays on screen until you close it (no auto-close)
    Read-Host "FAILED - press Enter to close"
  }
}
