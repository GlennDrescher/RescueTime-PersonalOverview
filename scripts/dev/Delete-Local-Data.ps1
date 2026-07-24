# ============================================================
# Delete-Local-Data.ps1  -  wipe the local data files for a full rebuild
#
# Deletes docs\archive.json and docs\data.json. With the archive gone, the
# NEXT run of Fetch-RescueTime-Data.ps1 (or the background "Local Fetch" task) starts from
# scratch: it backfills your ENTIRE history again and rebuilds data.json.
#
# Nothing else is touched - your dictionary, the site files and Secrets.ini all
# stay. Both deleted files are gitignored, so this never affects the repo/git.
#
#   Run:  .\scripts\dev\Delete-Local-Data.ps1      (from the repo root)
# ============================================================

# NOTE: we deliberately do NOT use a global "Stop" here. Previously a single
# locked or un-resolvable path threw and aborted the whole script, closing the
# window before anything was printed - which looked like "it just closes and
# deletes nothing". Now every risky step has its own try/catch and the window
# is ALWAYS held open at the end (finally) so you can read the result.
$ErrorActionPreference = "Continue"

# $ok decides the ending: a clean run (or a cancel) auto-closes after 10 s; any
# FAILURE (docs not found, a file that wouldn't delete, an unexpected error)
# stays on screen until you close it yourself.
$ok = $false
function Close-Window {
    Write-Host ""
    if ($script:ok) {
        Write-Host "Closing in 10 seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    } else {
        Read-Host "FAILED - press Enter to close"
    }
}

try {
    # ---- work out where docs\ is, ROBUSTLY -------------------------------
    # $PSScriptRoot is empty in some launch methods (dot-sourcing, pasting,
    # certain shortcuts). When it is empty, Join-Path threw and the script died
    # before the prompt. Fall back through every reliable source so the docs
    # folder is always found.
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDir) -and $PSCommandPath) { $scriptDir = Split-Path -Parent $PSCommandPath }
    if ([string]::IsNullOrWhiteSpace($scriptDir) -and $MyInvocation.MyCommand.Path) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }

    # docs is TWO levels up (this wrapper is in scripts\dev\ -> repo root -> docs)
    $docs = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "docs"
    $targets = @(
        (Join-Path $docs "archive.json"),
        (Join-Path $docs "data.json")
    )

    Write-Host ""
    Write-Host "Script folder : $scriptDir"
    Write-Host "Docs folder   : $docs"

    if (-not (Test-Path -LiteralPath $docs)) {
        Write-Host ""
        Write-Host "ERROR: docs folder not found at the path above." -ForegroundColor Red
        Write-Host "Make sure this file is inside the repo's scripts\dev\ folder and try again." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "This DELETES your local data so the next fetch does a FULL rebuild:" -ForegroundColor Yellow
    foreach ($t in $targets) {
        $tag = if (Test-Path -LiteralPath $t) { "[exists] " } else { "[missing]" }
        Write-Host ("  {0} {1}" -f $tag, $t)
    }
    Write-Host ""

    $ans = Read-Host "Type Y to delete (anything else cancels)"
    if ($ans -notmatch '^[Yy]') {
        Write-Host "Cancelled - nothing was deleted." -ForegroundColor Green
        $ok = $true          # a deliberate cancel is a clean exit, not a failure
        return
    }

    # ---- delete each file on its own, reporting success or failure -------
    Write-Host ""
    $deleted = 0; $failed = 0; $missing = 0
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) {
            $missing++
            Write-Host "SKIPPED (not there): $t" -ForegroundColor DarkGray
            continue
        }
        try {
            Remove-Item -LiteralPath $t -Force -ErrorAction Stop
            # a delete can "succeed" yet leave the file (e.g. a lock releases the
            # handle but not the entry) - confirm it is really gone.
            if (Test-Path -LiteralPath $t) { throw "file is still present after the delete call" }
            $deleted++
            Write-Host "DELETED: $t" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host "FAILED : $t" -ForegroundColor Red
            Write-Host ("         reason: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    }

    # ---- summary ---------------------------------------------------------
    Write-Host ""
    $summaryColor = if ($failed) { "Red" } else { "Green" }
    Write-Host ("Result: {0} deleted, {1} failed, {2} already missing." -f $deleted, $failed, $missing) -ForegroundColor $summaryColor
    $ok = ($failed -eq 0)    # any file that wouldn't delete = failure -> stay open

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "A file that won't delete is almost always LOCKED by another program" -ForegroundColor Yellow
        Write-Host "still reading it - usually the local website server or a running fetch." -ForegroundColor Yellow
        Write-Host "Stop those first (run 'Delete-Local-Website.ps1'), then re-run this." -ForegroundColor Yellow
    }
    elseif ($deleted -gt 0) {
        Write-Host "Next run of Fetch-RescueTime-Data.ps1 backfills the full history and rebuilds data.json." -ForegroundColor Green
    }
}
catch {
    # any UNEXPECTED error now shows here instead of the window silently vanishing
    Write-Host ""
    Write-Host "UNEXPECTED ERROR:" -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    Close-Window
}
