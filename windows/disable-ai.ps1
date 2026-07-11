<#
.SYNOPSIS
    Disable Windows 11 built-in AI features (Copilot, Recall, Click to Do,
    Edge Copilot, and AI in Search / Notepad).

.DESCRIPTION
    Applies machine-wide Group Policy registry values plus a few per-user
    toggles, and removes the standalone Copilot app. Self-elevates if not
    already running as Administrator (machine policies live under HKLM).

    Fully reversible with windows\enable-ai.ps1.

.NOTES
    Sign out / restart for all policies to take full effect.
    Some app-level generative features (Paint Cocreator, Photos generative
    fill) have no clean policy and are not covered here.
#>
[CmdletBinding()]
param(
    # Also remove Recall as a Windows optional feature (heavier than the policy disable).
    [switch]$RemoveRecallFeature
)

# --- self-elevate -----------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Elevation required - relaunching as Administrator..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($RemoveRecallFeature) { $argList += '-RemoveRecallFeature' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
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

Write-Host "`nRecall / Click to Do / Copilot (machine policy)" -ForegroundColor Cyan
Set-Reg $WAI 'DisableAIDataAnalysis' 1    # Windows Recall screen snapshots
Set-Reg $WAI 'DisableClickToDo'      1    # Click to Do
Set-Reg $WAI 'AllowRecallEnablement' 0    # block Recall being turned back on
Set-Reg $CP  'TurnOffWindowsCopilot' 1    # Windows Copilot experience

Write-Host "`nEdge Copilot / sidebar (machine policy)" -ForegroundColor Cyan
Set-Reg $ED 'HubsSidebarEnabled'   0      # Copilot sidebar button
Set-Reg $ED 'CopilotPageContext'   0      # don't send page content to Copilot
Set-Reg $ED 'ComposeInlineEnabled' 0      # "Compose" AI writing assistant

Write-Host "`nSearch AI (machine policy)" -ForegroundColor Cyan
Set-Reg $EX 'DisableSearchBoxSuggestions' 1

Write-Host "`nPer-user toggles" -ForegroundColor Cyan
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'    'IsAIEnabled'       0
Set-Reg 'HKCU:\Software\Microsoft\Notepad'                                  'CoPilotEnabled'    0

Write-Host "`nCopilot app" -ForegroundColor Cyan
$pkg = Get-AppxPackage -Name Microsoft.Copilot -ErrorAction SilentlyContinue
if ($pkg) {
    $pkg | Remove-AppxPackage
    Write-Host "  OK   Microsoft.Copilot removed" -ForegroundColor Green
} else {
    Write-Host "  --   Microsoft.Copilot not installed" -ForegroundColor DarkGray
}

if ($RemoveRecallFeature) {
    Write-Host "`nRecall optional feature" -ForegroundColor Cyan
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -NoRestart -ErrorAction Stop | Out-Null
        Write-Host "  OK   Recall feature disabled" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL Recall feature ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`nDone. Sign out or restart for all policies to take full effect." -ForegroundColor Yellow
