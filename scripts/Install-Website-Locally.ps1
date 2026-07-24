# ============================================================
# Install-Website-Locally.ps1  -  run the dashboard ALL the time (self-contained)
#
# Sets up the dashboard as a pair of background Scheduled Tasks that run with NO
# window, so they never interrupt you at the PC:
#
#   1. "Local Server"  - serves the site over http://localhost:8010 in the
#                        background; starts now and again at every login.
#   2. "Local Fetch"   - runs the SAME fetcher the GitHub Action uses every
#                        30 minutes so the data stays fresh.
#
# SELF-CONTAINED: everything the background site needs is COPIED into
#     %LOCALAPPDATA%\RescueTimeLocalSite
# (the site files, dictionary.json, the current data, a copy of the fetcher, and
# a copy of your Secrets.ini API key). The background server and fetch run
# entirely from THERE, so they never touch or lock your repo. Re-run this after
# changing the dictionary or the site to refresh that copy.
# "Delete-Local-Website.ps1" deletes the whole folder again.
#
# Check status any time with:   .\scripts\Status-Local-Website.ps1
#
#   Set up:  .\scripts\Install-Website-Locally.ps1     (from the repo root)
#   Undo:    .\scripts\Delete-Local-Website.ps1
#
# Requirements: Python on PATH and your API key in Secrets.ini in the REPO ROOT.
# ADMIN: registering the background tasks needs admin rights on most machines,
# so this script AUTO-ELEVATES (a UAC prompt appears). You can also just
# right-click it -> "Run as administrator". Run elevation on YOUR OWN account
# (so the tasks + %LOCALAPPDATA% copy belong to you).
# ============================================================

$ErrorActionPreference = "Stop"

# ---- ELEVATE: registering the background Scheduled Tasks needs admin rights on
#      most machines. If we're not already elevated, relaunch THIS script through
#      a UAC prompt and let the elevated copy do the work. ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if (-not $self) {
        Write-Host "Cannot find this script's own path to relaunch it elevated." -ForegroundColor Red
        Read-Host "FAILED - press Enter to close"; exit 1
    }
    Write-Host "Administrator rights are needed to register the background tasks." -ForegroundColor Yellow
    Write-Host "Relaunching with an elevation (UAC) prompt..." -ForegroundColor Yellow
    try {
        $hostExe = (Get-Process -Id $PID).Path      # this PowerShell host (powershell.exe / pwsh.exe)
        Start-Process -FilePath $hostExe -Verb RunAs `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`"" -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Host "Elevation was cancelled or blocked - can't continue without admin rights." -ForegroundColor Red
        Read-Host "FAILED - press Enter to close"; exit 1
    }
    exit 0    # the elevated copy takes over from here
}

# $ok stays $false until the very end of the try. The finally uses it to decide
# whether to auto-close (success) or stay open until you close it (failure).
$ok = $false

# Report the outcome: green success auto-closes after 10 s; a red FAILURE stays
# on screen until you close it yourself.
try {
    # ---- locations -----------------------------------------------------------
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir) -and $PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
    $RepoRoot    = Split-Path -Parent $scriptDir
    $RepoDocs    = Join-Path $RepoRoot "docs"
    $RepoSecrets = Join-Path $RepoRoot "Secrets.ini"
    $RepoFetcher = Join-Path $scriptDir "fetch-addition.py"

    $AppRoot     = Join-Path $env:LOCALAPPDATA "RescueTimeLocalSite"
    $AppDocs     = Join-Path $AppRoot "docs"
    $AppScripts  = Join-Path $AppRoot "scripts"
    $AppSecrets  = Join-Path $AppRoot "Secrets.ini"
    $AppFetcher  = Join-Path $AppScripts "fetch-addition.py"
    $AppServer   = Join-Path $AppRoot "server.py"

    $Port        = 8010
    $TaskFolder  = "\RescueTime\"
    $ServerTask  = "Local Server"
    $FetchTask   = "Local Fetch"
    $FetchEvery  = 30                      # minutes between data downloads

    # ---- the repo must have what the background copy needs -------------------
    if (-not (Test-Path -LiteralPath $RepoDocs))    { throw "docs folder not found: $RepoDocs  (run this from the repo's scripts\ folder)." }
    if (-not (Test-Path -LiteralPath $RepoFetcher)) { throw "Fetcher not found: $RepoFetcher" }
    if (-not (Test-Path -LiteralPath $RepoSecrets)) { throw "Secrets.ini not found in the repo root: $RepoSecrets  (needed so the background fetch has your API key)." }

    # ---- find Python (console + windowless variants) ------------------------
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $py) { throw "Python was not found on PATH - install it from python.org first." }
    $pythonExe = $py.Source
    # pythonw.exe runs with NO console window - ideal for a background server/fetch.
    $pythonwExe = Join-Path (Split-Path $pythonExe) "pythonw.exe"
    if (-not (Test-Path $pythonwExe)) { $pythonwExe = $pythonExe }   # fall back to python.exe

    # ---- build the self-contained appData copy ------------------------------
    # Mirrors the repo layout ( <root>\docs, <root>\scripts\fetch-addition.py,
    # <root>\Secrets.ini ) so the copied fetcher resolves ITS OWN paths to this
    # folder and reads/writes here, never in the repo.
    Write-Host "Building self-contained copy at $AppRoot ..." -ForegroundColor Cyan
    if (Test-Path -LiteralPath $AppRoot) { Remove-Item -LiteralPath $AppRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $AppDocs    -Force | Out-Null
    New-Item -ItemType Directory -Path $AppScripts -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoDocs "*") -Destination $AppDocs -Recurse -Force   # site + dictionary + current data/archive
    Copy-Item -LiteralPath $RepoFetcher -Destination $AppFetcher -Force
    Copy-Item -LiteralPath $RepoSecrets -Destination $AppSecrets -Force

    # ---- write the little static-file SERVER used by the background task -----
    # Why a dedicated server.py instead of "pythonw -m http.server":
    #   * it serves the docs\ folder EXPLICITLY (directory=), so it never depends
    #     on the task's working directory being applied (that was serving the
    #     wrong folder -> the page 404'd while the port still accepted TCP);
    #   * pythonw has NO console, so http.server's per-request logging to a None
    #     stderr could crash requests - we point stdout/stderr at server.log.
    $serverPy = @'
import os, sys, functools, http.server, socketserver
BASE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(BASE, "docs")
PORT = __PORT__
try:
    _log = open(os.path.join(BASE, "server.log"), "a", buffering=1, encoding="utf-8")
    sys.stdout = _log
    sys.stderr = _log
except Exception:
    pass
Handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=DOCS)
class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        print("Serving %s on http://127.0.0.1:%d/" % (DOCS, PORT))
        httpd.serve_forever()
'@
    $serverPy = $serverPy.Replace('__PORT__', "$Port")
    Set-Content -LiteralPath $AppServer -Value $serverPy -Encoding UTF8

    # ---- remove any previous copies of the tasks so this is safe to re-run ---
    foreach ($t in @($ServerTask, $FetchTask)) {
        $existing = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $t -ErrorAction SilentlyContinue
        if ($existing) { Unregister-ScheduledTask -TaskPath $TaskFolder -TaskName $t -Confirm:$false }
    }

    # ---- FIRST FETCH, in the FOREGROUND so you can watch it and so the site has
    #      real data before it opens. The first run backfills your whole history
    #      if there's no archive yet (can take a few minutes); later runs are the
    #      quick incremental fetch. Uses the CONSOLE python so its progress prints
    #      HERE (the scheduled task below uses windowless pythonw). If this fails
    #      (bad key / no internet) we stop now and schedule NOTHING. ----
    Write-Host ""
    Write-Host "Fetching your RescueTime data for the first time..." -ForegroundColor Cyan
    Write-Host "(the first run backfills your full history - this can take a few minutes; the progress prints below)" -ForegroundColor DarkGray
    Write-Host ""
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"   # let the fetcher's own progress/stderr stream without aborting us
    & $pythonExe $AppFetcher --refresh-days 3
    $fetchCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($fetchCode -ne 0) {
        throw "The initial data fetch failed (exit $fetchCode) - see the messages above. Usual causes: a wrong or empty API key in Secrets.ini, or no internet. Nothing was scheduled."
    }
    Write-Host ""
    Write-Host "Initial fetch complete - the site now has data." -ForegroundColor Green

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

    # ========================= 1) background server ==========================
    # Serves the appData copy (NOT the repo), so the repo is never locked.
    $serverSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)      # zero = no time limit (server runs forever)
    $serverAction  = New-ScheduledTaskAction -Execute $pythonwExe `
        -Argument "`"$AppServer`"" -WorkingDirectory $AppRoot
    $serverTrigger = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $ServerTask `
        -Action $serverAction -Trigger $serverTrigger -Settings $serverSettings -Principal $principal `
        -Description "Serves the RescueTime dashboard on http://127.0.0.1:$Port from $AppDocs (via server.py)." | Out-Null

    # ========================= 2) 30-minute fetcher ==========================
    # Runs the COPIED fetcher from the appData folder, so it reads Secrets.ini +
    # dictionary.json and writes data.json/archive.json all inside appData.
    $fetchSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15)   # a fetch should never take this long
    $fetchAction = New-ScheduledTaskAction -Execute $pythonwExe `
        -Argument "`"$AppFetcher`" --refresh-days 3" -WorkingDirectory $AppRoot
    $startAt = (Get-Date).AddMinutes($FetchEvery)   # first BACKGROUND run one interval out (we just fetched in the foreground)
    $fetchTriggerRepeat = New-ScheduledTaskTrigger -Once -At $startAt `
        -RepetitionInterval (New-TimeSpan -Minutes $FetchEvery) `
        -RepetitionDuration (New-TimeSpan -Days 3650)   # ~10 years. NOT [TimeSpan]::MaxValue - that serialises to P99999999DT... which Task Scheduler rejects as "out of range".
    $fetchTriggerLogon  = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $FetchTask `
        -Action $fetchAction -Trigger @($fetchTriggerRepeat, $fetchTriggerLogon) `
        -Settings $fetchSettings -Principal $principal `
        -Description "Downloads fresh RescueTime data every $FetchEvery minutes into $AppDocs." | Out-Null

    # ---- VERIFY the tasks are REALLY registered. Register-ScheduledTask can
    #      emit a NON-terminating "Access is denied" and let the script sail on
    #      to a false "success"; re-reading them here turns that into a real
    #      failure that the catch reports in red. ----
    $missing = @()
    if (-not (Get-ScheduledTask -TaskPath $TaskFolder -TaskName $ServerTask -ErrorAction SilentlyContinue)) { $missing += $ServerTask }
    if (-not (Get-ScheduledTask -TaskPath $TaskFolder -TaskName $FetchTask  -ErrorAction SilentlyContinue)) { $missing += $FetchTask }
    if ($missing.Count) {
        throw "Task Scheduler registration failed for: $($missing -join ', '). Almost always a rights problem - make sure you approved the UAC/elevation prompt (or right-click -> Run as administrator)."
    }

    # ---- bring the site up now (the data was already fetched above) ---------
    Start-ScheduledTask -TaskPath $TaskFolder -TaskName $ServerTask
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:$Port/index.html"                 # open it now that there's data

    Write-Host ""
    Write-Host "Local dashboard is set up and running (self-contained)." -ForegroundColor Green
    Write-Host "  Site:    http://localhost:$Port/index.html  (also serves after every login)" -ForegroundColor Green
    Write-Host "  Port:    $Port (separate from the dev Serve-Temporary-Website.ps1 on 8000, so both can run at once)" -ForegroundColor Green
    Write-Host "  Files:   $AppRoot" -ForegroundColor Green
    Write-Host "  Data:    refreshed every $FetchEvery minutes into docs\data.json (inside that folder)" -ForegroundColor Green
    Write-Host "  Tasks:   Task Scheduler -> $TaskFolder ($ServerTask, $FetchTask)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Check status:     .\scripts\Status-Local-Website.ps1" -ForegroundColor Green
    Write-Host "Stop + clean up:  .\scripts\Delete-Local-Website.ps1" -ForegroundColor Green
    $ok = $true
}
catch {
    Write-Host ""
    Write-Host "Setup FAILED:" -ForegroundColor Red
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
