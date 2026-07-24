# ============================================================
# Install and Start persistent Local Website.ps1  -  run the dashboard, ALL the time
#
# Unlike "Serve Temporary Website.ps1" (which serves the site only while its
# window is open), this script sets up the dashboard as a pair of background
# Scheduled Tasks so it keeps running and stays up to date on its own:
#
#   1. "Local Server"  - serves the docs folder over http://localhost:8000
#                        in the background (no window). It starts now and
#                        restarts automatically every time you log in to
#                        Windows (e.g. after a reboot).
#
#   2. "Local Fetch"   - the local "cron job": runs the SAME fetcher the
#                        GitHub Action uses (scripts\fetch-addition.py) every
#                        30 minutes, so docs\data.json is always fresh. The
#                        server serves whatever data.json currently holds, so
#                        the next time the page (re)loads it shows the data
#                        from the fetch that finished a minute or two earlier.
#
# Both tasks live under the Task Scheduler folder "\RescueTime\" so the
# companion script can find and remove them cleanly.
#
#   Set up:   .\scripts\"Install and Start persistent Local Website.ps1"   (from the repo root)
#   Undo:     .\scripts\"Stop Local persistent Website.ps1"
#
# Requirements: Python on PATH and your API key in Secrets.ini in the REPO ROOT
# (the fetcher reads it; it is gitignored).
#
# No administrator rights are needed: the tasks are registered for the
# current user only. If Windows policy blocks that, re-run this from an
# elevated PowerShell.
# ============================================================

$ErrorActionPreference = "Stop"

$Port        = 8000
$TaskFolder  = "\RescueTime\"
$ServerTask  = "Local Server"
$FetchTask   = "Local Fetch"
$FetchEvery  = 30                      # minutes between data downloads
# this script now lives in scripts\, so the repo root is its PARENT folder
$RepoRoot    = Split-Path $PSScriptRoot
$DocsDir     = Join-Path $RepoRoot "docs"
$FetchScript = Join-Path $RepoRoot "scripts\fetch-addition.py"

function Fail([string]$msg) {
  Write-Host ""
  Write-Host $msg -ForegroundColor Red
  Write-Host ""
  Read-Host "Setup FAILED - press Enter to close"
  exit 1
}

# --- locate Python (console + windowless variants) -----------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Fail "Python was not found on PATH - install it from python.org first." }
$pythonExe = $py.Source

# pythonw.exe runs with NO console window - ideal for a background server/fetch.
$pythonwExe = Join-Path (Split-Path $pythonExe) "pythonw.exe"
if (-not (Test-Path $pythonwExe)) { $pythonwExe = $pythonExe }   # fall back to python.exe

if (-not (Test-Path $DocsDir))     { Fail "docs folder not found: $DocsDir" }
if (-not (Test-Path $FetchScript)) { Fail "Fetcher not found: $FetchScript" }

# --- remove any previous copies so this script is safe to re-run ----------
foreach ($t in @($ServerTask, $FetchTask)) {
  $existing = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $t -ErrorAction SilentlyContinue
  if ($existing) { Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $t -Confirm:$false }
}

# --- shared settings: survive on battery, never time out, one instance ----
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit ([TimeSpan]::Zero)      # zero = no time limit (server must run forever)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# ========================= 1) background server ==========================
$serverAction = New-ScheduledTaskAction -Execute $pythonwExe `
  -Argument "-m http.server $Port" -WorkingDirectory $DocsDir
$serverTrigger = New-ScheduledTaskTrigger -AtLogOn      # restart on every login / after reboot

Register-ScheduledTask -TaskPath $TaskFolder -TaskName $ServerTask `
  -Action $serverAction -Trigger $serverTrigger -Settings $settings -Principal $principal `
  -Description "Serves the RescueTime dashboard on http://localhost:$Port in the background." | Out-Null

# ========================= 2) 30-minute fetcher ==========================
# Runs the identical fetcher the GitHub Action uses, in the repo root so it
# finds Secrets.ini. Repeats forever every $FetchEvery minutes, and also runs
# once at each login so the data is current the moment you sign in.
$fetchAction = New-ScheduledTaskAction -Execute $pythonwExe `
  -Argument "`"$FetchScript`" --refresh-days 3" -WorkingDirectory $RepoRoot

$startAt = (Get-Date).AddMinutes(1)          # first run a minute from now
$fetchTriggerRepeat = New-ScheduledTaskTrigger -Once -At $startAt `
  -RepetitionInterval (New-TimeSpan -Minutes $FetchEvery) `
  -RepetitionDuration ([TimeSpan]::MaxValue)
$fetchTriggerLogon  = New-ScheduledTaskTrigger -AtLogOn

$fetchSettings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 15)   # a fetch should never take this long

Register-ScheduledTask -TaskPath $TaskFolder -TaskName $FetchTask `
  -Action $fetchAction -Trigger @($fetchTriggerRepeat, $fetchTriggerLogon) `
  -Settings $fetchSettings -Principal $principal `
  -Description "Downloads fresh RescueTime data every $FetchEvery minutes for the local dashboard." | Out-Null

# --- start everything now -------------------------------------------------
Start-ScheduledTask -TaskPath $TaskFolder -TaskName $FetchTask    # prime the data
Start-ScheduledTask -TaskPath $TaskFolder -TaskName $ServerTask   # bring the site up
Start-Sleep -Seconds 2
Start-Process "http://localhost:$Port/index.html"                 # open it once so you can see it

Write-Host ""
Write-Host "Local dashboard is set up and running." -ForegroundColor Green
Write-Host "  Site:   http://localhost:$Port/index.html  (also serves after every login)" -ForegroundColor Green
Write-Host "  Data:   refreshed every $FetchEvery minutes into docs\data.json" -ForegroundColor Green
Write-Host "  Tasks:  Task Scheduler -> $TaskFolder ($ServerTask, $FetchTask)" -ForegroundColor Green
Write-Host ""
Write-Host "To undo all of this, run:  .\scripts\`"Stop Local persistent Website.ps1`"" -ForegroundColor Green
Write-Host ""
Write-Host "Closing in 6 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 6
