# ============================================================
# Delete Local Data.ps1  -  wipe the local data files for a full rebuild
#
# Deletes docs\archive.json and docs\data.json. With the archive gone, the
# NEXT run of Fetch-Data.ps1 (or the background "Local Fetch" task) starts from
# scratch: it backfills your ENTIRE history again and rebuilds data.json.
#
# Nothing else is touched - your dictionary, the site files and Secrets.ini all
# stay. Both deleted files are gitignored, so this never affects the repo/git.
#
#   Run:  .\scripts\"Delete Local Data.ps1"      (from the repo root)
# ============================================================

$ErrorActionPreference = "Stop"

# docs is one level up from this script's home in scripts\
$docs = Join-Path (Split-Path $PSScriptRoot) "docs"
$targets = @(
  (Join-Path $docs "archive.json"),
  (Join-Path $docs "data.json")
)

Write-Host ""
Write-Host "This DELETES your local data so the next fetch does a FULL rebuild:" -ForegroundColor Yellow
foreach ($t in $targets) {
  $tag = if (Test-Path $t) { "[exists] " } else { "[missing]" }
  Write-Host ("  {0} {1}" -f $tag, $t)
}
Write-Host ""
$ans = Read-Host "Type Y to delete (anything else cancels)"
if ($ans -notmatch '^[Yy]') {
  Write-Host "Cancelled - nothing was deleted." -ForegroundColor Green
  Start-Sleep -Seconds 2
  exit 0
}

$deleted = 0
foreach ($t in $targets) {
  if (Test-Path $t) {
    Remove-Item -LiteralPath $t -Force
    $deleted++
    Write-Host "Deleted $t" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host ("Done - {0} file(s) deleted." -f $deleted) -ForegroundColor Green
Write-Host "Next run of Fetch-Data.ps1 backfills the full history and rebuilds data.json." -ForegroundColor Green
Write-Host ""
Write-Host "Closing in 6 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 6
