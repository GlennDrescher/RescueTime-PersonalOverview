# ============================================================
# Delete-Local-Website.ps1  -  undo "Install-Website-Locally.ps1"
#
# Fully tears down the always-on background site:
#   - unregisters "\RescueTime\Local Server" and "\RescueTime\Local Fetch"
#   - stops the python http.server still serving on port 8010
#   - DELETES the self-contained folder %LOCALAPPDATA%\RescueTimeLocalSite
#     (site copy, data, the copied fetcher and the copied Secrets.ini)
#
# Your repo and its files are NOT touched - only the background copy and its two
# tasks are removed. Re-run the install script any time to bring it all back.
#
# ADMIN: removing the Scheduled Tasks needs admin rights, so this AUTO-ELEVATES
# (a UAC prompt appears); or right-click -> "Run as administrator".
#
#   Run:  .\scripts\Delete-Local-Website.ps1     (from the repo root)
# ============================================================

$ErrorActionPreference = "Stop"

# ---- ELEVATE: removing the Scheduled Tasks needs admin rights on most machines.
#      If we're not already elevated, relaunch THIS script through a UAC prompt. ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if (-not $self) {
        Write-Host "Cannot find this script's own path to relaunch it elevated." -ForegroundColor Red
        Read-Host "FAILED - press Enter to close"; exit 1
    }
    Write-Host "Administrator rights are needed to remove the background tasks." -ForegroundColor Yellow
    Write-Host "Relaunching with an elevation (UAC) prompt..." -ForegroundColor Yellow
    try {
        $hostExe = (Get-Process -Id $PID).Path
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

# $ok stays $false until the end of the try. The finally uses it to decide
# whether to auto-close (success) or stay open until you close it (failure).
$ok = $false

# Report the outcome: green success auto-closes after 10 s; a red FAILURE stays
# on screen until you close it yourself.
try {
    $Port       = 8010
    $TaskFolder = "\RescueTime\"
    $Tasks      = @("Local Server", "Local Fetch")
    $AppRoot    = Join-Path $env:LOCALAPPDATA "RescueTimeLocalSite"

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

    # verify the removals actually happened (Unregister-ScheduledTask can emit a
    # NON-terminating access-denied and leave the task in place)
    $stillThere = @()
    foreach ($t in $Tasks) {
        if (Get-ScheduledTask -TaskPath $TaskFolder -TaskName $t -ErrorAction SilentlyContinue) { $stillThere += $t }
    }
    if ($stillThere.Count) {
        throw "Could not remove task(s): $($stillThere -join ', '). Almost always a rights problem - approve the UAC/elevation prompt (or right-click -> Run as administrator)."
    }

    # --- kill the running server BEFORE deleting its folder (else the files are
    #     locked and the delete fails) --------------------------------------
    $killed = 0
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        $procIds = $conns | Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($procId in $procIds) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            # only stop Python processes - don't touch anything else on the port
            if ($p -and $p.ProcessName -match "python") {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                $killed++
            }
        }
    } catch {
        # Get-NetTCPConnection may be unavailable on very old Windows; the tasks
        # are already unregistered, so the server won't come back on next login.
    }

    # --- delete the self-contained appData folder -----------------------------
    $folderMsg = ""; $folderOk = $true
    if (Test-Path -LiteralPath $AppRoot) {
        Start-Sleep -Milliseconds 500        # give the killed server a moment to release its files
        $folderOk = $false
        for ($i = 0; $i -lt 4 -and -not $folderOk; $i++) {
            try { Remove-Item -LiteralPath $AppRoot -Recurse -Force -ErrorAction Stop; $folderOk = $true }
            catch { Start-Sleep -Seconds 1 }
        }
        $folderMsg = if ($folderOk) { "Deleted app folder: $AppRoot" }
                     else { "COULD NOT delete app folder (something is still holding it): $AppRoot" }
    } else {
        $folderMsg = "App folder already gone: $AppRoot"
    }

    # --- summary --------------------------------------------------------------
    Write-Host ""
    if ($removed.Count) { Write-Host ("Removed tasks: " + ($removed -join ", ")) -ForegroundColor Green }
    if ($missing.Count) { Write-Host ("Not found (already gone): " + ($missing -join ", ")) -ForegroundColor Yellow }
    Write-Host ("Stopped server process(es): {0}" -f $killed) -ForegroundColor Green
    if ($folderOk) { Write-Host $folderMsg -ForegroundColor Green } else { Write-Host $folderMsg -ForegroundColor Red }
    Write-Host ""
    if ($folderOk) { Write-Host "Local dashboard is fully torn down." -ForegroundColor Green }
    else { Write-Host "Tasks + server stopped, but the folder could not be removed - delete it manually if it persists." -ForegroundColor Yellow }
    $ok = $folderOk    # a folder that wouldn't delete counts as a failure (stay open)
}
catch {
    Write-Host ""
    Write-Host "Teardown FAILED:" -ForegroundColor Red
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
