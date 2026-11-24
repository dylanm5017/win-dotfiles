<#
.SYNOPSIS
    Restore the committed Windhawk mod setup (windhawk/state) onto this machine: mod sources,
    enable state, and per-mod settings. Best-effort companion to Export-Windhawk.ps1.

.DESCRIPTION
    Windhawk has no official import; this writes the captured state back into %ProgramData%\Windhawk
    and HKLM\SOFTWARE\Windhawk. It is invoked by `winsmooth -Apply` when windhawk/state exists, or
    can be run directly. It does nothing when the machine already matches. Otherwise:
      1. Stop the Windhawk service.
      2. Back up the current Mods/ModsWritable registry + ModsSource to %LOCALAPPDATA%\win-dotfiles\
         windhawk-backups\<timestamp> (so the change is reversible).
      3. Copy committed sources into %ProgramData%\Windhawk\ModsSource and import the .reg files.
      4. Restore compiled binaries if they were captured (-IncludeCompiled export); otherwise
         Windhawk recompiles each mod from source on next launch.
      5. Start the service and restart Explorer so the mods take effect.

    Stopping Windhawk kills some services it has injected into, so those are also added to its
    process exclusion list, which Windhawk reads only when it starts. If only that list needs a
    change, the mods and Explorer are left alone.

    Self-elevates (HKLM + the Windhawk service need admin). Brittle by nature: mod settings schemas
    can change across mod/Windhawk updates. Re-run Export-Windhawk.ps1 after changing mods.

.EXAMPLE
    .\windhawk\Import-Windhawk.ps1
.EXAMPLE
    .\windhawk\Import-Windhawk.ps1 -Force
#>
[CmdletBinding()]
param(
    # Import the mods even when the machine already matches.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $PSScriptRoot 'state'
$regDir = Join-Path $stateRoot 'registry'
$srcDir = Join-Path $stateRoot 'ModsSource'
$engineModsBackup = Join-Path $stateRoot 'EngineMods'
$programData = Join-Path $env:ProgramData 'Windhawk'
$pdModsSource = Join-Path $programData 'ModsSource'
$engineMods = Join-Path $programData 'Engine\Mods'
$engineSettings = 'HKLM:\SOFTWARE\Windhawk\Engine\Settings'
$excludedProcesses = 'tailscaled.exe', 'cowork-svc.exe'

if (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'manifest.json'))) {
    Write-Warning "No captured Windhawk state at $stateRoot. Run Export-Windhawk.ps1 first."
    return
}
if (-not (Test-Path -LiteralPath $programData)) {
    Write-Warning "Windhawk not installed at $programData. Install RamenSoftware.Windhawk, then re-run."
    return
}

function Read-RegFile {
    param([Parameter(Mandatory)][string]$Path)

    $values = @{}
    $key = ''
    $text = (Get-Content -LiteralPath $Path -Raw -Encoding Unicode) -replace '\\\r?\n\s*', ''
    foreach ($line in $text -split '\r?\n') {
        if ($line -match '^\[(.+)\]$') {
            $key = $Matches[1]
            $values[$key] = ''
        }
        elseif ($line -match '^("(?:[^"\\]|\\.)*"|@)=(.*)$') {
            $values["$key|$($Matches[1])"] = $Matches[2]
        }
    }
    $values
}

function Test-FilesMatch {
    param([string]$From, [string]$To)

    if (-not (Test-Path -LiteralPath $From)) { return $true }
    foreach ($file in Get-ChildItem -LiteralPath $From -File -Recurse) {
        $copy = Join-Path $To ([IO.Path]::GetRelativePath($From, $file.FullName))
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) { return $false }
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $copy).Hash) { return $false }
    }
    $true
}

function Test-ModsMatch {
    # Windhawk rewrites LibraryFileName and SettingsChangeTime itself, and ModsWritable holds the mods'
    # own running data, so a difference there is not a changed setup. Extra live mods are ignored too:
    # an import never removes them.
    if (-not (Test-FilesMatch $srcDir $pdModsSource)) { return $false }
    if (-not (Test-FilesMatch $engineModsBackup $engineMods)) { return $false }

    $export = [IO.Path]::GetTempFileName()
    try {
        & reg.exe export 'HKLM\SOFTWARE\Windhawk\Engine\Mods' $export /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        $live = Read-RegFile $export
    }
    finally {
        Remove-Item -LiteralPath $export -Force -ErrorAction SilentlyContinue
    }

    $wanted = Read-RegFile (Join-Path $regDir 'Mods.reg')
    if ($wanted.Count -eq 0) { return $false }
    foreach ($name in $wanted.Keys) {
        if ($name -match '\|"(LibraryFileName|SettingsChangeTime)"$') { continue }
        if (-not $live.ContainsKey($name) -or $live[$name] -cne $wanted[$name]) { return $false }
    }
    $true
}

function Get-ExcludedByWindhawk {
    $value = (Get-ItemProperty -LiteralPath $engineSettings -ErrorAction SilentlyContinue).Exclude
    "$value" -split '\|' | Where-Object { $_ }
}

$importMods = $Force -or -not (Test-ModsMatch)
$missingExclusions = @($excludedProcesses | Where-Object { $_ -notin @(Get-ExcludedByWindhawk) })
if (-not $importMods -and -not $missingExclusions) {
    Write-Host 'Windhawk already matches windhawk\state; nothing to import.' -ForegroundColor DarkGray
    return
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Elevation required - relaunching as Administrator...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Force) { $argList += '-Force' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
}

$svc = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
$wasRunning = $svc -and $svc.Status -eq 'Running'
if ($wasRunning) { Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue }

try {
    if ($missingExclusions) {
        if (-not (Test-Path -LiteralPath $engineSettings)) { New-Item -Path $engineSettings -Force | Out-Null }
        $exclude = (@(Get-ExcludedByWindhawk) + $missingExclusions) -join '|'
        Set-ItemProperty -LiteralPath $engineSettings -Name Exclude -Value $exclude -Type String
        Write-Host "Excluded from Windhawk: $($missingExclusions -join ', ')" -ForegroundColor Green
    }

    if ($importMods) {
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
        if (Test-Path -LiteralPath $engineModsBackup) {
            New-Item -ItemType Directory -Path $engineMods -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $engineModsBackup '*') -Destination $engineMods -Recurse -Force
        }

        # 4. Import registry (enable state + settings).
        & reg.exe import (Join-Path $regDir 'Mods.reg') | Out-Null
        $modsWritableReg = Join-Path $regDir 'ModsWritable.reg'
        if (Test-Path -LiteralPath $modsWritableReg) { & reg.exe import $modsWritableReg | Out-Null }
    }
}
finally {
    if ($wasRunning) { Start-Service -Name Windhawk -ErrorAction SilentlyContinue }
}

if (-not $importMods) { return }

# Mods apply to newly drawn windows; recycle Explorer so context-menu/title-bar mods take effect.
try { Stop-Process -Name explorer -Force -ErrorAction Stop } catch {}

Write-Host 'Restored Windhawk mods from windhawk\state.' -ForegroundColor Green
if (-not (Test-Path -LiteralPath $engineModsBackup)) {
    Write-Host 'No binaries captured: open Windhawk once (or reboot) so it recompiles each mod from source.' -ForegroundColor Yellow
}
