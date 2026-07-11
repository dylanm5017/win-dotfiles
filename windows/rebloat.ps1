<#
.SYNOPSIS
    Reverse windows\debloat.ps1 - restore Windows diagnostics/telemetry defaults.

.DESCRIPTION
    Clears the telemetry / error-reporting policies, restores the DiagTrack and
    dmwappushservice start types, re-enables the CEIP/feedback scheduled tasks,
    and turns suggested content back on. Self-elevates if needed.

    Does NOT reinstall apps removed by debloat.ps1 - get those from the Store.
#>
[CmdletBinding()]
param()

# --- self-elevate -----------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Elevation required - relaunching as Administrator..." -ForegroundColor Yellow
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    return
}

function Remove-Reg($Path, $Name) {
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue }
    Write-Host ("  OK   cleared {0}" -f $Name) -ForegroundColor Green
}

$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)

Write-Host "`nClearing telemetry / error-reporting policies" -ForegroundColor Cyan
Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications'
Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled'

Write-Host "`nRestoring services (Windows defaults)" -ForegroundColor Cyan
# DiagTrack defaults to Automatic; dmwappushservice to Manual
$svcDefaults = @{ DiagTrack = 'Automatic'; dmwappushservice = 'Manual' }
foreach ($svc in $svcDefaults.Keys) {
    try {
        Set-Service $svc -StartupType $svcDefaults[$svc] -ErrorAction Stop
        if ($svcDefaults[$svc] -eq 'Automatic') { Start-Service $svc -ErrorAction SilentlyContinue }
        Write-Host "  OK   $svc -> $($svcDefaults[$svc])" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL $svc ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`nRe-enabling CEIP / feedback scheduled tasks" -ForegroundColor Cyan
foreach ($t in $tasks) {
    $path = (Split-Path $t -Parent) + '\'
    $name = Split-Path $t -Leaf
    try {
        Enable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
        Write-Host "  OK   enabled $name" -ForegroundColor Green
    } catch {
        Write-Host "  --   $name (not present)" -ForegroundColor DarkGray
    }
}

Write-Host "`nSuggested content (per-user)" -ForegroundColor Cyan
if (-not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager')) {
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Force | Out-Null
}
New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 1 -PropertyType DWord -Force | Out-Null
Write-Host "  OK   ContentDeliveryAllowed = 1" -ForegroundColor Green

Write-Host "`nDone. Reinstall any removed apps from the Microsoft Store if wanted." -ForegroundColor Yellow
