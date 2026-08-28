<#
.SYNOPSIS
  Build the Hearth desktop release: supervisor, voice engine, backend bundle,
  then the client.

.DESCRIPTION
  This runs the four steps documented in wiki/releasing.md, in the one order
  that works, and fails loudly at the first that does not. The wiki stays the
  explanation; this is the execution.

    1. supervisor      cargo build --release in backend/supervisor
    2. voice engine    scripts/build_omnivoice.sh        (skippable)
    3. backend bundle  scripts/pack_backend.sh
    4. client          npm run tauri build in desktop-client

  Order is load-bearing. pack_backend.sh stages whatever supervisor binary is
  already on disk, so packing before building ships last week's supervisor;
  that exact staleness shipped an installer whose supervisor did not know
  HEARTH_DEEP_MODEL_FILE, and every install planning a non-12B tier died at
  boot (2026-08-08). pack_backend.sh has a freshness gate for it now, and this
  script keeps the order anyway.

  Step 4 must be `npm run tauri build`, never `cargo build --release` on its
  own: cargo compiles only the Rust and leaves the webview pointing at
  tauri.conf.json's devUrl, so the app launches to "localhost refused to
  connect" with no Vite running. (Learned on the Valinor client, 2026-08-27.)

  The artifact comes out at the WORKSPACE root, not under
  desktop-client/src-tauri/target, because the tauri crate is a member of the
  root workspace.

  Exits non-zero on any failure so an agentic task can gate on it.

.PARAMETER SkipVoice
  Skip the voice engine. The bundle then installs text-only, which
  pack_backend.sh warns about rather than refusing.

.PARAMETER SkipSupervisor
  Reuse the supervisor binary already on disk. pack_backend.sh still refuses a
  binary older than its sources.

.PARAMETER EngramMcpSrc
  Where the engram-mcp checkout lives. pack_backend.sh hard errors without one,
  deliberately: a bundle missing the memory client is a silent memory
  regression.

.EXAMPLE
  pwsh -File scripts/build_release.ps1

.EXAMPLE
  pwsh -File scripts/build_release.ps1 -SkipVoice -SkipSupervisor
#>
[CmdletBinding()]
param(
    [switch]$SkipVoice,
    [switch]$SkipSupervisor,
    [string]$EngramMcpSrc = '../engram-mcp'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Step($n, $msg) { Write-Host "`n==> [$n/4] $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "`nFAILED: $msg" -ForegroundColor Red; exit 1 }

function Invoke-Step($cmd, $dir, $what) {
    Push-Location $dir
    try {
        & ([scriptblock]::Create($cmd))
        if ($LASTEXITCODE -ne 0) { Die "$what exited $LASTEXITCODE" }
    }
    finally { Pop-Location }
}

Step 1 'Supervisor'
$supDir = Join-Path $repo 'backend\supervisor'
$sup = Join-Path $supDir 'target\release\hearth-supervisor.exe'
if ($SkipSupervisor) {
    if (-not (Test-Path $sup)) { Die "no supervisor at $sup and -SkipSupervisor was given" }
    Warn "reusing $((Get-Item $sup).LastWriteTime)"
}
else {
    if (-not (Test-Path $supDir)) { Die "no supervisor source at $supDir" }
    Invoke-Step 'cargo build --release' $supDir 'cargo build'
    if (-not (Test-Path $sup)) { Die "cargo reported success but $sup is missing" }
    Ok ("{0:N1} MB, {1}" -f ((Get-Item $sup).Length / 1MB), (Get-Item $sup).LastWriteTime)
}

Step 2 'Voice engine'
if ($SkipVoice) {
    Warn 'skipped; the bundle will install text-only unless a binary is already staged'
}
else {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bash) { Die 'bash is not on PATH; build_omnivoice.sh needs Git Bash or WSL' }
    Invoke-Step 'bash scripts/build_omnivoice.sh' $repo 'build_omnivoice.sh'
    Ok 'built'
}

Step 3 'Backend bundle'
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { Die 'bash is not on PATH; pack_backend.sh needs Git Bash or WSL' }
# wiki/releasing.md documents ../engram-mcp, which is the shape a fresh clone
# takes. A working machine often has it somewhere else, and hearth.env already
# records where, so ask the configuration before giving up on a path that only
# exists in the documentation.
$candidates = @((Join-Path $repo $EngramMcpSrc))
$envFile = 'D:\Hearth\config\hearth.env'
if (Test-Path $envFile) {
    $configured = (Get-Content $envFile |
        Where-Object { $_ -match '^HEARTH_ENGRAM_MCP_PATH=' } |
        Select-Object -First 1) -replace '^HEARTH_ENGRAM_MCP_PATH=', ''
    if ($configured) { $candidates += $configured }
}
$resolved = $null
foreach ($c in $candidates) {
    $r = Resolve-Path -Path $c -ErrorAction SilentlyContinue
    if ($r -and (Test-Path (Join-Path $r 'engram_mcp'))) { $resolved = $r; break }
}
if (-not $resolved) {
    Die @"
no engram-mcp checkout found. Looked at:
$($candidates | ForEach-Object { "  $_" } | Out-String)
pack_backend.sh refuses without it, deliberately: a bundle missing the memory
client is a silent memory regression. Clone it, or pass -EngramMcpSrc:
  git clone https://github.com/XXJones21/engram-mcp.git $EngramMcpSrc
"@
}
Ok "engram-mcp at $resolved"
$env:ENGRAM_MCP_SRC = $resolved
Invoke-Step 'bash scripts/pack_backend.sh' $repo 'pack_backend.sh'
$tarball = Join-Path $repo 'desktop-client\src-tauri\resources\backend.tar.gz'
if (-not (Test-Path $tarball)) { Die "pack_backend.sh reported success but $tarball is missing" }
Ok ("backend.tar.gz {0:N1} MB" -f ((Get-Item $tarball).Length / 1MB))

Step 4 'Client'
$client = Join-Path $repo 'desktop-client'
if (-not (Test-Path (Join-Path $client 'node_modules'))) {
    Warn 'node_modules missing; running npm install'
    Invoke-Step 'npm install' $client 'npm install'
}
# `npm run tauri build`, never cargo alone: it runs beforeBuildCommand
# (tsc && vite build) first, so the binary ships the built frontend.
Invoke-Step 'npm run tauri build' $client 'tauri build'

Step 4 'Verifying'
# The tauri crate is a workspace member, so the artifact lands at the ROOT
# target directory, not under desktop-client/src-tauri/target.
$bundles = Get-ChildItem -Path (Join-Path $repo 'target\release\bundle') -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.msi', '.exe', '.dmg', '.app' } |
    Sort-Object LastWriteTime -Descending
if (-not $bundles) { Die 'no bundle under target/release/bundle; the build produced nothing to ship' }
foreach ($b in $bundles | Select-Object -First 4) {
    Ok ("{0}  {1:N1} MB  {2}" -f $b.Name, ($b.Length / 1MB), $b.LastWriteTime)
}

Write-Host "`nDone. See wiki/releasing.md for signing and the release itself." -ForegroundColor Green
