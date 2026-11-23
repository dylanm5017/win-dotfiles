<#
.SYNOPSIS
    Starts Wave Link a fixed delay after sign-in instead of through its own Store startup task.
.DESCRIPTION
    Wave Link 3 often crashes in CoreMessagingXP.dll within minutes of boot, and starting hidden in
    the tray can leave its channels silent. Launching it late, through the Start entry, opens its
    window. The side dock then places that window (a no-op without the ultrawide).

    A separate task from Set-SideDock, which exits early when the ultrawide is absent and would
    then never start Wave Link.
.PARAMETER Register
    Create the per-user logon scheduled task. winsmooth also turns off Wave Link's own startup task.
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 600)][int]$DelaySeconds = 60,
    [int]$TimeoutSeconds = 60,
    [switch]$Register
)

$appId = 'Elgato.WaveLink_g54w8ztgkx496!App'

if ($Register) {
    $taskName = 'win-dotfiles Start-WaveLink'
    $arguments = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TimeoutSeconds $TimeoutSeconds"
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $trigger.Delay = "PT${DelaySeconds}S"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
    Write-Host "Registered scheduled task '$taskName' (${DelaySeconds}s after sign-in)." -ForegroundColor Green
    return
}

if (-not (Get-Process -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue)) {
    Start-Process "shell:AppsFolder\$appId"
}

$window = $null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not $window -and (Get-Date) -lt $deadline) {
    $window = Get-Process -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
    if (-not $window) { Start-Sleep -Milliseconds 500 }
}
if (-not $window) {
    Write-Output "Wave Link window did not appear within $TimeoutSeconds s."
    exit 1
}
Start-Sleep -Milliseconds 1500
& (Join-Path $PSScriptRoot 'Set-SideDock.ps1')
