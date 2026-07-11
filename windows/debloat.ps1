<#
.SYNOPSIS
    Reduce Windows 11 diagnostics, telemetry, and bloat to a practical floor.

.DESCRIPTION
    Sets diagnostic data to the lowest level a consumer SKU honors, disables
    the telemetry service, Windows Error Reporting, and the CEIP/feedback
    scheduled tasks, turns off "suggested content", and removes a small set
    of unwanted Store apps. Self-elevates if not already Administrator.

    Reversible (except app removal) with windows\rebloat.ps1.

.NOTES
    AllowTelemetry=1 (Required) is the minimum Home/Pro will honor; 0 (Security)
    is Enterprise/Education only and is silently treated as 1 elsewhere.
    Removed apps must be reinstalled from the Microsoft Store.
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

function Set-Reg($Path, $Name, $Value) {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        Write-Host ("  OK   {0,-32} = {1}" -f $Name, $Value) -ForegroundColor Green
    } catch {
        Write-Host ("  FAIL {0,-32} ({1})" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

# CEIP / feedback / compatibility telemetry scheduled tasks
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)

# Store apps to remove (current user + deprovision so new profiles don't get them)
$apps = 'Microsoft.GetHelp','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay','Microsoft.ZuneMusic'

Write-Host "`nTelemetry / diagnostic data" -ForegroundColor Cyan
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'              1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
foreach ($svc in 'DiagTrack','dmwappushservice') {
    try {
        Stop-Service $svc -Force -ErrorAction SilentlyContinue
        Set-Service  $svc -StartupType Disabled -ErrorAction Stop
        Write-Host "  OK   service $svc disabled" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL service $svc ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`nWindows Error Reporting" -ForegroundColor Cyan
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1

Write-Host "`nCEIP / feedback scheduled tasks" -ForegroundColor Cyan
foreach ($t in $tasks) {
    $path = (Split-Path $t -Parent) + '\'
    $name = Split-Path $t -Leaf
    try {
        Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
        Write-Host "  OK   disabled $name" -ForegroundColor Green
    } catch {
        Write-Host "  --   $name (not present)" -ForegroundColor DarkGray
    }
}

Write-Host "`nSuggested content (per-user)" -ForegroundColor Cyan
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 0

Write-Host "`nRemove Store apps" -ForegroundColor Cyan
foreach ($a in $apps) {
    $p = Get-AppxPackage -Name $a -ErrorAction SilentlyContinue
    if ($p) {
        try { $p | Remove-AppxPackage -ErrorAction Stop; Write-Host "  OK   removed $a" -ForegroundColor Green }
        catch { Write-Host "  FAIL $a ($($_.Exception.Message))" -ForegroundColor Red }
    } else { Write-Host "  --   $a absent" -ForegroundColor DarkGray }
    # Deprovision so a fresh user profile doesn't get it back
    $prov = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $a
    if ($prov) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
              Write-Host "  OK   deprovisioned $a" -ForegroundColor Green }
        catch { Write-Host "  FAIL deprovision $a ($($_.Exception.Message))" -ForegroundColor Red }
    }
}

Write-Host "`nDone. Sign out or restart for service/telemetry changes to settle." -ForegroundColor Yellow
