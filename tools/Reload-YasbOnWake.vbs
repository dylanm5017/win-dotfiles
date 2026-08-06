' Silent launcher for the yasb display-wake reload, wired to the scheduled task registered by
' Reload-YasbOnWake.ps1 -Register. Same reason as Show-ThemePicker.vbs: pwsh is a console app, and
' a scheduled task launching it directly pops a console window on screen at the exact moment the
' monitors come back. wscript.exe is GUI-subsystem, so Run() with window style 0 starts pwsh with
' its console already hidden and nothing ever flashes.
Dim sh, fso, ps1
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Reload-YasbOnWake.ps1")
sh.Run "pwsh -NoProfile -NoLogo -File """ & ps1 & """", 0, False
