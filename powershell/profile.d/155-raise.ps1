# Raise-or-launch: focus an app that is already open instead of starting a second copy, the way a
# Hyprland dispatcher does. The whkd `win + <letter>` bindings in komorebi/whkdrc call the same
# script, so the hotkey and the shell command always agree on what `browser` means.
#
# The work lives in tools/Raise-App.ps1 rather than here because whkd runs it from its own
# long-lived PowerShell session, which never loads this profile.

$WinRaiseScript = Join-Path $WinDotfilesRoot 'tools\Raise-App.ps1'

function Invoke-WinRaiseOrLaunch { & $WinRaiseScript @args }

function Get-WinRaiseApps { & $WinRaiseScript -List }

Set-Alias -Name raise -Value Invoke-WinRaiseOrLaunch -Force
Set-Alias -Name apps -Value Get-WinRaiseApps -Force
