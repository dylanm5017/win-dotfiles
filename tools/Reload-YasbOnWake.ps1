#requires -Version 5.1
<#
.SYNOPSIS
    Reload yasb when the displays wake, working around a stale monitor handle in yasb.

.DESCRIPTION
    Clicking a komorebi workspace chip stops doing anything after the monitors sleep and wake.
    komorebi is not at fault -- it re-enumerates monitors on wake and `komorebic state` stays
    correct. The break is entirely inside yasb:

      * core/bar.py caches `self.monitor_hwnd = get_monitor_hwnd(int(self.winId()))` once in
        __init__ and hands that value to every widget. `on_geometry_changed` repositions the bar
        but never recomputes it.
      * Windows reissues HMONITOR handles when the displays come back, so the cached value now
        names a monitor that no longer exists.
      * widgets/komorebi/workspaces.py resolves its screen with
        `self._screen_hwnd = self.monitor_hwnd or get_monitor_hwnd(...)`. The `or` always prefers
        the stale cached value, so `get_screen_by_hwnd` returns None and the widget can never
        recover on its own. Every click then throws
        `TypeError: 'NoneType' object is not subscriptable` into ~/.config/yasb/yasb.log.

    Reloading yasb re-runs the bar constructor and recaptures the handle, so this registers a
    scheduled task that does exactly that on the wake transition.

    The trigger is Kernel-Power event 566 filtered to `NextSessionType = 0`. That field is what
    separates the two directions: the sleep transition logs NextSessionType 1, the wake logs 0.
    Filtering matters rather than just firing on both -- a reload while the panels are still off
    would recapture handles that Windows is about to reissue again, leaving the bar just as
    broken. Event 107 is registered as a second trigger to cover a full S3/hibernate resume.

    Verified against yasb v2.0.5 (latest as of 2026-08-06). There is no upstream issue for this
    yet; if one lands and ships a fix, run with -Unregister and delete this script.

.EXAMPLE
    Reload-YasbOnWake.ps1 -Register

.EXAMPLE
    Reload-YasbOnWake.ps1 -Status

.EXAMPLE
    Reload-YasbOnWake.ps1 -Unregister
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    # Install the scheduled task.
    [Parameter(ParameterSetName = 'Register')]
    [switch]$Register,

    # Remove the scheduled task.
    [Parameter(ParameterSetName = 'Unregister')]
    [switch]$Unregister,

    # Show whether the task is installed, and when it last ran.
    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Reload YASB on display wake'
$TaskPath = '\win-dotfiles\'
$LogPath = Join-Path $env:LOCALAPPDATA 'win-dotfiles\yasb-wake-reload.log'

# NextSessionType 0 is the wake edge; the matching sleep transition reports 1.
$WakeQuery = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=566]] and *[EventData[Data[@Name='NextSessionType']='0']]</Select></Query></QueryList>
'@

$ResumeQuery = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=107]]</Select></Query></QueryList>
'@

function Write-Log {
    param([string]$Message)

    try {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Trimmed rather than rotated: this only ever appends one line per wake.
        if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 128KB) {
            Set-Content -LiteralPath $LogPath -Value (Get-Content -LiteralPath $LogPath -Tail 200)
        }
        Add-Content -LiteralPath $LogPath -Value ("{0}  {1}" -f (Get-Date -Format 's'), $Message)
    }
    catch { }
}

function New-EventTrigger {
    param([string]$Subscription, [string]$Delay)

    $class = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $trigger = New-CimInstance -CimClass $class -ClientOnly
    $trigger.Subscription = $Subscription
    $trigger.Enabled = $true
    # The wake event lands before the display topology has settled; reloading too early just
    # recaptures handles that are still about to change.
    $trigger.Delay = $Delay
    $trigger
}

function Register-WakeTask {
    $vbs = Join-Path $PSScriptRoot 'Reload-YasbOnWake.vbs'
    if (-not (Test-Path -LiteralPath $vbs -PathType Leaf)) {
        throw "Missing silent launcher: $vbs"
    }

    $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f $vbs)

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -StartWhenAvailable

    $triggers = @(
        (New-EventTrigger -Subscription $WakeQuery -Delay 'PT6S'),
        (New-EventTrigger -Subscription $ResumeQuery -Delay 'PT10S')
    )

    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath `
        -Action $action -Principal $principal -Settings $settings -Trigger $triggers `
        -Description 'Reloads yasb after the displays wake, so the komorebi workspace widget picks up the reissued monitor handles. See tools/Reload-YasbOnWake.ps1.' `
        -Force | Out-Null

    Write-Host "Registered '$TaskName' under $TaskPath" -ForegroundColor Green
    Write-Host "Log: $LogPath"
}

function Unregister-WakeTask {
    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Not registered." -ForegroundColor Yellow
        return
    }

    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
    Write-Host "Removed '$TaskName'." -ForegroundColor Green
}

function Show-Status {
    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Not registered. Run: Reload-YasbOnWake.ps1 -Register" -ForegroundColor Yellow
        return
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
    [pscustomobject]@{
        State          = $existing.State
        LastRunTime    = $info.LastRunTime
        LastTaskResult = $info.LastTaskResult
        NumberOfMissed = $info.NumberOfMissedRuns
    } | Format-List

    if (Test-Path -LiteralPath $LogPath) {
        Write-Host "Recent reloads:" -ForegroundColor Cyan
        Get-Content -LiteralPath $LogPath -Tail 10
    }
    else {
        Write-Host "No reloads logged yet ($LogPath)."
    }
}

function Invoke-Reload {
    if (-not (Get-Process -Name yasb -ErrorAction SilentlyContinue)) {
        Write-Log 'yasb not running; skipped.'
        return
    }

    $yasbc = Get-Command -Name yasbc -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $yasbc) {
        $fallback = Join-Path $env:ProgramFiles 'YASB\yasbc.exe'
        if (Test-Path -LiteralPath $fallback -PathType Leaf) { $yasbc = Get-Item -LiteralPath $fallback }
    }
    if (-not $yasbc) {
        Write-Log 'yasbc.exe not found; skipped.'
        return
    }

    try {
        & $yasbc.Source reload 2>&1 | Out-Null
        Write-Log 'Reloaded yasb after display wake.'
    }
    catch {
        Write-Log "Reload failed: $($_.Exception.Message)"
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'Register' { Register-WakeTask }
    'Unregister' { Unregister-WakeTask }
    'Status' { Show-Status }
    default { Invoke-Reload }
}
