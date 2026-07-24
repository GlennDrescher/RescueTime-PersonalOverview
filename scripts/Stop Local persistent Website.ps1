# ============================================================
# Stop Local persistent Website.ps1  -  undo "Install and Start persistent Local Website.ps1"
#
# Removes the two background Scheduled Tasks created by the install script and
# stops the local server that is currently running, so nothing is left behind:
#
#   - unregisters "\RescueTime\Local Server" and "\RescueTime\Local Fetch"
#   - stops the http.server process still serving the site (port 8000)
#
# Your files and data are NOT touched - only the background server and the
# 30-minute fetch task are removed. Re-run the install script any time to
# bring it all back.
#
#   Run:  .\scripts\"Stop Local persistent Website.ps1"     (from the repo root)
# ============================================================

$ErrorActionPreference = "Stop"

$Port       = 8000
$TaskFolder = "\RescueTime\"
$Tasks      = @("Local Server", "Local Fetch")

$removed = @()
$missing = @()

# --- stop + unregister the scheduled tasks --------------------------------
foreach ($t in $Tasks) {
  $task = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $t -ErrorAction SilentlyContinue
  if ($task) {
    try { Stop-ScheduledTask -TaskPath $TaskFolder -TaskName $t -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $t -Confirm:$false
    $removed += $t
  } else {
    $missing += $t
  }
}

# --- kill the running server (whatever is listening on the port) ----------
$killed = 0
try {
  $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  $pids  = $conns | Select-Object -ExpandProperty OwningProcess -Unique
  foreach ($procId in $pids) {
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    # only stop Python processes - don't touch anything else that might use the port
    if ($p -and $p.ProcessName -match "python") {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      $killed++
    }
  }
} catch {
  # Get-NetTCPConnection may be unavailable on very old Windows; the task is
  # already unregistered, so the server won't come back on next login anyway.
}

Write-Host ""
if ($removed.Count) { Write-Host ("Removed tasks: " + ($removed -join ", ")) -ForegroundColor Green }
if ($missing.Count) { Write-Host ("Not found (already gone): " + ($missing -join ", ")) -ForegroundColor Yellow }
Write-Host ("Stopped server process(es): {0}" -f $killed) -ForegroundColor Green
Write-Host ""
Write-Host "Local dashboard is fully torn down." -ForegroundColor Green
Write-Host ""
Write-Host "Closing in 5 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 5
