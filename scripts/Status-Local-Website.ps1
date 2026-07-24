# ============================================================
# Status-Local-Website.ps1  -  is the background site alive?
#
# Read-only check for the always-on site set up by Install-Website-Locally.ps1.
# Prints a snapshot (nothing is changed), then STAYS OPEN until you press Enter
# or close the window yourself - so it's readable however you launch it:
#   - whether each Scheduled Task is installed and its state
#   - when the fetch last ran, its result, and the next scheduled run
#   - whether the web server is actually answering on port 8010
#   - when the data was last refreshed (data.json timestamp)
#
#   Run:  .\scripts\Status-Local-Website.ps1     (from the repo root)
# ============================================================

$ErrorActionPreference = "Continue"   # a status read-out should never abort

$Port       = 8010
$TaskFolder = "\RescueTime\"
$ServerTask = "Local Server"
$FetchTask  = "Local Fetch"
$AppRoot    = Join-Path $env:LOCALAPPDATA "RescueTimeLocalSite"
$AppDocs    = Join-Path $AppRoot "docs"
$DataJson   = Join-Path $AppDocs "data.json"

function Show-Task([string]$label, [string]$name) {
    $task = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $name -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ("  {0,-12}: " -f $label) -NoNewline
        Write-Host "NOT INSTALLED" -ForegroundColor Red
        return
    }
    $state = [string]$task.State
    $stateColor = if ($state -eq "Running" -or $state -eq "Ready") { "Green" } else { "Yellow" }
    Write-Host ("  {0,-12}: " -f $label) -NoNewline
    Write-Host $state -ForegroundColor $stateColor -NoNewline

    $info = Get-ScheduledTaskInfo -TaskPath $TaskFolder -TaskName $name -ErrorAction SilentlyContinue
    if ($info) {
        $last = if ($info.LastRunTime) { $info.LastRunTime.ToString("yyyy-MM-dd HH:mm") } else { "never" }
        $res  = $info.LastTaskResult
        $resTxt = if ($res -eq 0) { "OK" } elseif ($res -eq 267009) { "running now" } else { "code $res" }
        $next = if ($info.NextRunTime) { $info.NextRunTime.ToString("yyyy-MM-dd HH:mm") } else { "-" }
        Write-Host ("   | last run {0} ({1}) | next {2}" -f $last, $resTxt, $next)
    } else {
        Write-Host ""
    }
}

Write-Host ""
Write-Host "RescueTime local persistent site - status" -ForegroundColor Cyan
$appTag = if (Test-Path -LiteralPath $AppRoot) { "(exists)" } else { "(MISSING - run Install-Website-Locally.ps1)" }
Write-Host ("  App folder  : {0} {1}" -f $AppRoot, $appTag)

Write-Host ""
Write-Host ("Scheduled tasks (Task Scheduler -> {0}):" -f $TaskFolder)
Show-Task "Server task" $ServerTask
Show-Task "Fetch task"  $FetchTask

# --- is the server actually SERVING the page? Do a REAL HTTP GET of index.html,
#     not just a TCP connect - a bare connect can succeed (port "open") while the
#     actual requests still fail (wrong folder = 404, or a crashing handler). ---
Write-Host ""
$srvState = "down"; $srvCode = $null
try {
    $resp = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/index.html" -f $Port) -UseBasicParsing -TimeoutSec 4
    $srvCode = [int]$resp.StatusCode
    $srvState = if ($srvCode -eq 200) { "up" } else { "bad" }
} catch {
    if ($_.Exception.Response) {
        $srvState = "bad"
        try { $srvCode = [int]$_.Exception.Response.StatusCode } catch {}
    } else {
        $srvState = "down"
    }
}
Write-Host ("  Web server  : ") -NoNewline
switch ($srvState) {
    "up"    { Write-Host ("UP - serving http://localhost:{0}/index.html" -f $Port) -ForegroundColor Green }
    "bad"   { Write-Host ("RESPONDING but /index.html gave HTTP {0} - not serving the site correctly (re-run Install)" -f $srvCode) -ForegroundColor Yellow }
    default { Write-Host ("DOWN - nothing is serving on port {0}" -f $Port) -ForegroundColor Red }
}

# --- when did the data last refresh? (data.json "generated_at") -------------
if (Test-Path -LiteralPath $DataJson) {
    $txt = Get-Content -Raw -LiteralPath $DataJson
    if ($txt -match '"generated_at"\s*:\s*"([^"]+)"') {
        try {
            $gen = [datetimeoffset]::Parse($Matches[1]).LocalDateTime
            $age = (Get-Date) - $gen
            $ageTxt = if ($age.TotalMinutes -lt 60) { "{0:n0} min ago" -f $age.TotalMinutes }
                      elseif ($age.TotalHours -lt 48) { "{0:n1} hours ago" -f $age.TotalHours }
                      else { "{0:n1} days ago" -f $age.TotalDays }
            $ageColor = if ($age.TotalMinutes -le 45) { "Green" } elseif ($age.TotalHours -le 3) { "Yellow" } else { "Red" }
            Write-Host ("  Last fetch  : ") -NoNewline
            Write-Host ("{0}  ({1})" -f $gen.ToString("yyyy-MM-dd HH:mm"), $ageTxt) -ForegroundColor $ageColor
        } catch {
            Write-Host "  Last fetch  : could not read the timestamp in data.json" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Last fetch  : no timestamp found in data.json" -ForegroundColor Yellow
    }
} else {
    Write-Host ("  Last fetch  : no data.json yet ({0})" -f $DataJson) -ForegroundColor Red
}
Write-Host ""
# Keep the window open until the user is done reading (Enter, or close the
# window). This never auto-closes, so a double-click launch stays readable.
Read-Host "Press Enter (or close this window) to exit"
