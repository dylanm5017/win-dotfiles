<#
.SYNOPSIS
    Re-enable Windows 11 built-in AI features disabled by windows\disable-ai.ps1.

.DESCRIPTION
    Removes the policy values and restores the per-user toggles to their
    AI-on defaults. Self-elevates if not already Administrator. Does NOT
    reinstall the Copilot app (get it from the Microsoft Store) or re-add
    the Recall optional feature if it was removed with -RemoveRecallFeature.

.NOTES
    Sign out / restart for the policy changes to take full effect.
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
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Write-Host ("  OK   removed {0}" -f $Name) -ForegroundColor Green
    } catch {
        Write-Host ("  FAIL {0} ({1})" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

function Set-Reg($Path, $Name, $Value) {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        Write-Host ("  OK   {0,-30} = {1}" -f $Name, $Value) -ForegroundColor Green
    } catch {
        Write-Host ("  FAIL {0,-30} ({1})" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

$WAI = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
$CP  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
$ED  = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$EX  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'

Write-Host "`nClearing machine policies" -ForegroundColor Cyan
Remove-Reg $WAI 'DisableAIDataAnalysis'
Remove-Reg $WAI 'DisableClickToDo'
Remove-Reg $WAI 'AllowRecallEnablement'
Remove-Reg $CP  'TurnOffWindowsCopilot'
Remove-Reg $ED  'HubsSidebarEnabled'
Remove-Reg $ED  'CopilotPageContext'
Remove-Reg $ED  'ComposeInlineEnabled'
Remove-Reg $EX  'DisableSearchBoxSuggestions'

Write-Host "`nRestoring per-user toggles (AI on)" -ForegroundColor Cyan
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 1
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'    'IsAIEnabled'       1
Set-Reg 'HKCU:\Software\Microsoft\Notepad'                                  'CoPilotEnabled'    1

Write-Host "`nDone. Sign out or restart to fully restore. Reinstall the Copilot" -ForegroundColor Yellow
Write-Host "app from the Microsoft Store if you want it back." -ForegroundColor Yellow
