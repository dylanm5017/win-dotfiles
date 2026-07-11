<#
.SYNOPSIS
    Restore the committed Windhawk mod setup (windhawk/state) onto this machine: mod sources,
    enable state, and per-mod settings. Best-effort companion to Export-Windhawk.ps1.

.DESCRIPTION
    Windhawk has no official import; this writes the captured state back into %ProgramData%\Windhawk
    and HKLM\SOFTWARE\Windhawk. It is invoked by `winsmooth -Apply` when windhawk/state exists, or
    can be run directly. Steps:
      1. Stop the Windhawk service.
      2. Back up the current Mods/ModsWritable registry + ModsSource to %LOCALAPPDATA%\win-dotfiles\
         windhawk-backups\<timestamp> (so the change is reversible).
      3. Copy committed sources into %ProgramData%\Windhawk\ModsSource and import the .reg files.
      4. Restore compiled binaries if they were captured (-IncludeCompiled export); otherwise
         Windhawk recompiles each mod from source on next launch.
      5. Start the service and restart Explorer so the mods take effect.

    Self-elevates (HKLM + the Windhawk service need admin). Brittle by nature: mod settings schemas
    can change across mod/Windhawk updates. Re-run Export-Windhawk.ps1 after changing mods.

.EXAMPLE
    .\windhawk\Import-Windhawk.ps1
#>
[CmdletBinding()]
param()

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Elevation required - relaunching as Administrator...' -ForegroundColor Yellow
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $PSScriptRoot 'state'
$regDir = Join-Path $stateRoot 'registry'
$srcDir = Join-Path $stateRoot 'ModsSource'
$programData = Join-Path $env:ProgramData 'Windhawk'
$pdModsSource = Join-Path $programData 'ModsSource'

if (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'manifest.json'))) {
    Write-Warning "No captured Windhawk state at $stateRoot. Run Export-Windhawk.ps1 first."
    return
}
if (-not (Test-Path -LiteralPath $programData)) {
    Write-Warning "Windhawk not installed at $programData. Install RamenSoftware.Windhawk, then re-run."
    return
}

$svc = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
$wasRunning = $svc -and $svc.Status -eq 'Running'
if ($wasRunning) { Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue }

try {
    # 1. Back up current state (reversible).
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupDir = Join-Path $env:LOCALAPPDATA "win-dotfiles\windhawk-backups\$stamp"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    & reg.exe export 'HKLM\SOFTWARE\Windhawk\Engine\Mods' (Join-Path $backupDir 'Mods.reg') /y | Out-Null
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable') {
        & reg.exe export 'HKLM\SOFTWARE\Windhawk\Engine\ModsWritable' (Join-Path $backupDir 'ModsWritable.reg') /y | Out-Null
    }
    if (Test-Path -LiteralPath $pdModsSource) {
        Copy-Item -LiteralPath $pdModsSource -Destination (Join-Path $backupDir 'ModsSource') -Recurse -Force
    }
    Write-Host "Backed up current Windhawk state to $backupDir" -ForegroundColor DarkGray

    # 2. Restore sources.
    New-Item -ItemType Directory -Path $pdModsSource -Force | Out-Null
    Get-ChildItem $srcDir -Filter '*.wh.cpp' -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $pdModsSource -Force }

    # 3. Restore compiled binaries if captured.
    $engineModsBackup = Join-Path $stateRoot 'EngineMods'
    if (Test-Path -LiteralPath $engineModsBackup) {
        $engineMods = Join-Path $programData 'Engine\Mods'
        New-Item -ItemType Directory -Path $engineMods -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $engineModsBackup '*') -Destination $engineMods -Recurse -Force
    }

    # 4. Import registry (enable state + settings).
    & reg.exe import (Join-Path $regDir 'Mods.reg') | Out-Null
    $modsWritableReg = Join-Path $regDir 'ModsWritable.reg'
    if (Test-Path -LiteralPath $modsWritableReg) { & reg.exe import $modsWritableReg | Out-Null }
}
finally {
    if ($wasRunning) { Start-Service -Name Windhawk -ErrorAction SilentlyContinue }
}

# Mods apply to newly drawn windows; recycle Explorer so context-menu/title-bar mods take effect.
try { Stop-Process -Name explorer -Force -ErrorAction Stop } catch {}

Write-Host 'Restored Windhawk mods from windhawk\state.' -ForegroundColor Green
if (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'EngineMods'))) {
    Write-Host 'No binaries captured: open Windhawk once (or reboot) so it recompiles each mod from source.' -ForegroundColor Yellow
}
