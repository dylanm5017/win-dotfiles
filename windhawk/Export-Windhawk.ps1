<#
.SYNOPSIS
    Capture the current Windhawk mod setup (enabled mods + their settings + sources) into the
    repo so it can be restored on this or another machine with Import-Windhawk.ps1 / winsmooth.

.DESCRIPTION
    Windhawk has no official config export; its state lives in the registry under
    HKLM\SOFTWARE\Windhawk and in %ProgramData%\Windhawk. This script captures the mod-relevant
    parts into windhawk/state/:
      - registry/Mods.reg          (HKLM\SOFTWARE\Windhawk\Engine\Mods        - enable state + per-mod Settings)
      - registry/ModsWritable.reg  (HKLM\SOFTWARE\Windhawk\Engine\ModsWritable - mod-written settings)
      - ModsSource/<id>.wh.cpp      (the mod source, so Windhawk can recompile on restore)
      - manifest.json               (mod ids + disabled flag + version, for review/diffs)
      - EngineMods/                 (compiled DLLs - only with -IncludeCompiled; arch/version specific)

    By default compiled binaries are NOT captured (they are large and ABI/version specific); on
    restore Windhawk recompiles each mod from its source on next launch. Use -IncludeCompiled for
    an exact, no-recompile same-machine restore.

    Self-elevates (HKLM + the Windhawk service need admin). Run after configuring mods in the
    Windhawk UI to commit your setup; see windhawk/mods.md for the curated list.

.EXAMPLE
    .\windhawk\Export-Windhawk.ps1
.EXAMPLE
    .\windhawk\Export-Windhawk.ps1 -IncludeCompiled
#>
[CmdletBinding()]
param(
    # Also copy the compiled mod DLLs (Engine\Mods) for an exact same-machine restore (large, binary).
    [switch]$IncludeCompiled
)

# --- self-elevate -----------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Elevation required - relaunching as Administrator...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($IncludeCompiled) { $argList += '-IncludeCompiled' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
}

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $PSScriptRoot 'state'
$regDir = Join-Path $stateRoot 'registry'
$srcDir = Join-Path $stateRoot 'ModsSource'
$programData = Join-Path $env:ProgramData 'Windhawk'
$modsRegKey = 'HKLM\SOFTWARE\Windhawk\Engine\Mods'
$modsWritableRegKey = 'HKLM\SOFTWARE\Windhawk\Engine\ModsWritable'

if (-not (Test-Path -LiteralPath $programData)) {
    Write-Error "Windhawk not found at $programData. Install RamenSoftware.Windhawk and configure mods first."
    return
}

function Stop-WindhawkService {
    $svc = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue
        Write-Host 'Stopped Windhawk service for a consistent snapshot.' -ForegroundColor DarkGray
        return $true
    }
    return $false
}
function Start-WindhawkService { param([bool]$WasRunning)
    if ($WasRunning) { Start-Service -Name Windhawk -ErrorAction SilentlyContinue; Write-Host 'Restarted Windhawk service.' -ForegroundColor DarkGray }
}

# Reset the captured state so removed mods don't linger in the repo.
if (Test-Path -LiteralPath $stateRoot) { Remove-Item -LiteralPath $stateRoot -Recurse -Force }
New-Item -ItemType Directory -Path $regDir -Force | Out-Null
New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

$wasRunning = Stop-WindhawkService
try {
    # 1. Registry: mod enable-state + settings (reg.exe handles REG_BINARY settings + subtrees).
    & reg.exe export $modsRegKey (Join-Path $regDir 'Mods.reg') /y | Out-Null
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Windhawk\Engine\ModsWritable') {
        & reg.exe export $modsWritableRegKey (Join-Path $regDir 'ModsWritable.reg') /y | Out-Null
    }

    # 2. Mod sources (so Windhawk can recompile on restore).
    $sources = Get-ChildItem (Join-Path $programData 'ModsSource') -Filter '*.wh.cpp' -ErrorAction SilentlyContinue
    foreach ($s in $sources) { Copy-Item -LiteralPath $s.FullName -Destination $srcDir -Force }

    # 3. Optional compiled binaries (exact same-machine restore).
    if ($IncludeCompiled) {
        $engineMods = Join-Path $programData 'Engine\Mods'
        if (Test-Path -LiteralPath $engineMods) {
            Copy-Item -LiteralPath $engineMods -Destination (Join-Path $stateRoot 'EngineMods') -Recurse -Force
        }
    }

    # 4. Human-readable manifest (mod id + enabled state + version).
    $mods = foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\Windhawk\Engine\Mods' -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath
        [PSCustomObject]@{ id = $k.PSChildName; disabled = [int]($p.Disabled); version = "$($p.Version)" }
    }
    [PSCustomObject]@{
        exportedUtc     = (Get-Date).ToUniversalTime().ToString('o')
        includeCompiled = [bool]$IncludeCompiled
        modCount        = @($mods).Count
        mods            = @($mods | Sort-Object id)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateRoot 'manifest.json') -Encoding utf8
}
finally {
    Start-WindhawkService -WasRunning $wasRunning
}

Write-Host "Captured $(@($mods).Count) Windhawk mods into windhawk\state." -ForegroundColor Green
Write-Host 'Review the diff and commit windhawk/state to version-control your Windhawk setup.' -ForegroundColor Cyan
if (-not $IncludeCompiled) {
    Write-Host 'Sources + settings only (no binaries): Windhawk recompiles each mod on first launch after a restore.' -ForegroundColor DarkGray
}
