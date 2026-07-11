#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a machine from win-dotfiles: install packages, link the PowerShell profile,
    and apply workstation tuning. Idempotent — safe to re-run.

.DESCRIPTION
    Steps:
      1. Install Scoop (if missing) + git, add the buckets and apps in packages/scoop.json.
      2. Import the curated winget set in packages/winget.json.
      3. Symlink the PowerShell profile to this repo.
      4. Run `winsmooth -Apply` (links komorebi/terminal/WezTerm configs and applies tuning).

    Run from an elevated PowerShell so the winsmooth Defender exclusions and machine policies
    can be applied; non-elevated runs still work but skip the elevated-only tuning.

.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -SkipWinget -SkipWinsmooth   # packages-from-scoop + profile link only
#>
[CmdletBinding()]
param(
    [switch]$SkipScoop,
    [switch]$SkipWinget,
    [switch]$SkipFonts,
    [switch]$SkipWinsmooth
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$packagesRoot = Join-Path $repoRoot 'packages'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Test-CommandExists { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# 1. Scoop ----------------------------------------------------------------------------------
if (-not $SkipScoop) {
    if (-not (Test-CommandExists scoop)) {
        Write-Step 'Installing Scoop'
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }
    else {
        Write-Host 'Scoop already installed.' -ForegroundColor DarkGray
    }

    # git is required before any bucket can be added.
    if (-not (Test-CommandExists git)) {
        Write-Step 'Installing git (required for scoop buckets)'
        scoop install git
    }

    $scoopManifestPath = Join-Path $packagesRoot 'scoop.json'
    $scoopManifest = Get-Content -LiteralPath $scoopManifestPath -Raw | ConvertFrom-Json

    $existingBuckets = @(scoop bucket list | ForEach-Object { $_.Name })
    foreach ($bucket in $scoopManifest.buckets) {
        if ($existingBuckets -notcontains $bucket.Name) {
            Write-Step "Adding scoop bucket: $($bucket.Name)"
            scoop bucket add $bucket.Name $bucket.Source
        }
    }

    foreach ($app in $scoopManifest.apps) {
        if ($SkipFonts -and $app.Source -eq 'nerd-fonts') {
            Write-Host "Skipping font: $($app.Name)" -ForegroundColor DarkGray
            continue
        }
        Write-Step "scoop install $($app.Source)/$($app.Name)"
        # scoop install is idempotent: it reports already-installed apps and moves on.
        scoop install "$($app.Source)/$($app.Name)"
    }
}

# 2. winget ---------------------------------------------------------------------------------
if (-not $SkipWinget) {
    if (Test-CommandExists winget) {
        Write-Step 'Importing winget packages'
        # --ignore-unavailable: keep going if an ID is missing on this SKU/region.
        winget import --import-file (Join-Path $packagesRoot 'winget.json') `
            --accept-package-agreements --accept-source-agreements --ignore-unavailable --ignore-versions
    }
    else {
        Write-Warning 'winget not found; skipping winget import.'
    }
}

# 3. PowerShell profile link ----------------------------------------------------------------
Write-Step 'Linking PowerShell profile'
$powerShellRoot = Join-Path $HOME 'Documents\PowerShell'
New-Item -ItemType Directory -Path $powerShellRoot -Force | Out-Null
$profileLink = Join-Path $powerShellRoot 'Microsoft.PowerShell_profile.ps1'
$repoProfile = Join-Path $repoRoot 'powershell\profile.ps1'

$existing = Get-Item -LiteralPath $profileLink -Force -ErrorAction SilentlyContinue
if ($existing) { Remove-Item -LiteralPath $profileLink -Force }
try {
    New-Item -ItemType SymbolicLink -Path $profileLink -Target $repoProfile -Force | Out-Null
    Write-Host "Linked $profileLink -> $repoProfile" -ForegroundColor Green
}
catch {
    Copy-Item -LiteralPath $repoProfile -Destination $profileLink -Force
    Write-Warning "Symlink denied; copied profile instead. Enable Developer Mode for symlinks."
}

# 3b. Git hooks -----------------------------------------------------------------------------
# Route git hooks to the repo's committed hooks/ so the pre-commit config validator runs. Every
# repo config is symlinked live, so this gate stops a malformed config from being committed.
if (Test-CommandExists git) {
    Write-Step 'Enabling repo git hooks (core.hooksPath)'
    git -C $repoRoot config core.hooksPath hooks
}
else {
    Write-Warning 'git not found; skipping core.hooksPath setup (pre-commit config validation).'
}

# 4. Workstation tuning (links komorebi/terminal/WezTerm + applies tuning) -------------------
if (-not $SkipWinsmooth) {
    if (Test-CommandExists pwsh) {
        Write-Step 'Applying workstation tuning (winsmooth -Apply)'
        # Run in a fresh, profile-loaded pwsh so winsmooth and its config-linking helpers exist.
        pwsh -NoLogo -Command 'winsmooth -Apply'
    }
    else {
        Write-Warning 'pwsh (PowerShell 7) not found; open it and run "winsmooth -Apply" manually.'
    }
}

Write-Host ''
Write-Host 'Done. Open a new PowerShell to load the profile.' -ForegroundColor Green
if ($SkipWinsmooth) {
    Write-Host 'Next: run "winsmooth -Apply" from an elevated PowerShell to link configs and tune the host.' -ForegroundColor Yellow
}
