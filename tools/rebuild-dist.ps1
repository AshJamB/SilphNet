<#
.SYNOPSIS
  Rebuilds dist/silphnet.zip from mod/silphnet/ and verifies it byte-for-byte.

.DESCRIPTION
  Does the same two things Claude has been doing by hand (via a Python
  script in its own sandbox) after every mod/silphnet/ change:

    1. Repackage - zips everything under mod/silphnet/ into
       dist/silphnet.zip, with every file placed under a "silphnet/"
       prefix inside the zip (so installing it drops a silphnet/ folder,
       not the mod's files loose at the zip root).
    2. Byte-verify - re-opens the zip it just wrote and compares every
       entry's SHA256 against the real source file, so a partial/corrupt
       write or a stale cached entry can never slip through silently.

  Also runs a best-effort Lua syntax check on main.lua and mod.card via
  `luac -p` if a Lua install happens to be on PATH - most Windows setups
  won't have this, so it's skipped with a clear message rather than
  failing the whole script when it's missing. The byte-verify step above
  is the one that actually matters for catching a broken package; the
  syntax check is a bonus when it's available.

  Exists specifically as a fallback for whenever Claude's own sandbox
  shell is unavailable (e.g. the platform outage this was built during) -
  everything it does can also be done by hand in phpMyAdmin/a Python
  shell/etc, this just means you're never fully blocked waiting on that.

.EXAMPLE
  Right-click this file in Explorer -> Run with PowerShell

.EXAMPLE
  From a PowerShell prompt, from anywhere:
    powershell -ExecutionPolicy Bypass -File "C:\GitHub\SilphNet\tools\rebuild-dist.ps1"
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Resolve paths relative to THIS script's own location, not whatever
# directory it happens to be run from - so it works the same whether
# double-clicked, run from the repo root, or run from tools\ itself.
$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot  = Join-Path $repoRoot 'mod\silphnet'
$zipPath  = Join-Path $repoRoot 'dist\silphnet.zip'

Write-Host "SilphNet dist rebuild" -ForegroundColor Cyan
Write-Host "  Source: $srcRoot"
Write-Host "  Output: $zipPath"
Write-Host ""

if (-not (Test-Path $srcRoot)) {
    Write-Error "Can't find mod\silphnet under $repoRoot - is this script still inside tools\ in the real repo checkout?"
    exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------------------------------------------------------------------------
# Step 1: repackage
# ---------------------------------------------------------------------------
# Staged in a throwaway temp folder (repo\silphnet\<files>) rather than
# zipping mod\silphnet\ directly, purely so the zip's internal paths come
# out as "silphnet/main.lua" etc rather than just "main.lua" at the zip
# root - ZipFile.CreateFromDirectory always zips relative to the folder
# you point it at, so the "silphnet" folder name itself has to actually
# exist on disk as the thing being zipped.
$stageRoot = Join-Path $env:TEMP ("silphnet_stage_" + [guid]::NewGuid())
$stageDir  = Join-Path $stageRoot 'silphnet'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

try {
    Copy-Item -Path (Join-Path $srcRoot '*') -Destination $stageDir -Recurse -Force

    $zipDir = Split-Path -Parent $zipPath
    if (-not (Test-Path $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}
finally {
    Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Repackaged: $zipPath" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------------
# Step 2: byte-verify
# ---------------------------------------------------------------------------
# Same SHA256-per-file comparison this project has always run by hand
# after packaging - confirms every file that went INTO the zip comes back
# OUT byte-for-byte identical.
$allOk = $true
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($entry in $zip.Entries) {
        # Windows PowerShell (.NET Framework) writes zip entry names with
        # backslashes ("silphnet\main.lua"); modern .NET/PowerShell 7 uses
        # forward slashes ("silphnet/main.lua") per the zip spec. Strip
        # either so this works the same on both.
        $relPath = $entry.FullName -replace '^silphnet[\\/]', ''
        $srcFile = Join-Path $srcRoot $relPath

        if (-not (Test-Path $srcFile)) {
            Write-Host ("MISSING SOURCE  {0}" -f $entry.FullName) -ForegroundColor Red
            $allOk = $false
            continue
        }

        $srcHash = (Get-FileHash -Path $srcFile -Algorithm SHA256).Hash

        $entryStream = $entry.Open()
        $ms = New-Object System.IO.MemoryStream
        $entryStream.CopyTo($ms)
        $entryStream.Close()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $zipHash = [System.BitConverter]::ToString($sha256.ComputeHash($ms.ToArray())) -replace '-', ''
        $ms.Dispose()
        $sha256.Dispose()

        if ($srcHash -eq $zipHash) {
            Write-Host ("OK              {0}" -f $entry.FullName) -ForegroundColor Green
        } else {
            Write-Host ("MISMATCH        {0}" -f $entry.FullName) -ForegroundColor Red
            $allOk = $false
        }
    }
}
finally {
    $zip.Dispose()
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 3: Lua syntax check (best-effort - only if luac is actually installed)
# ---------------------------------------------------------------------------
$luac = Get-Command luac -ErrorAction SilentlyContinue
if ($luac) {
    foreach ($luaFile in @('main.lua', 'mod.card')) {
        $path = Join-Path $srcRoot $luaFile
        & $luac.Path -p $path
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("Lua syntax OK   {0}" -f $luaFile) -ForegroundColor Green
        } else {
            Write-Host ("Lua syntax FAIL {0} - see luac output above" -f $luaFile) -ForegroundColor Red
            $allOk = $false
        }
    }
} else {
    Write-Host "Lua syntax check SKIPPED - no 'luac' found on PATH (install Lua if you want this step too)" -ForegroundColor Yellow
}
Write-Host ""

if ($allOk) {
    Write-Host "ALL OK - dist/silphnet.zip is ready to commit." -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILURES PRESENT - do NOT commit this zip. Scroll up for details." -ForegroundColor Red
    exit 1
}
