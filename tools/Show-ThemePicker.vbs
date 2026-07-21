' Silent launcher for the win-dotfiles theme picker, wired to the yasb theme_status widget.
' pwsh is a console app, so launching it directly (as yasb does) flashes a console window for a
' frame before -WindowStyle Hidden can hide it. wscript.exe is a GUI-subsystem host: Run() with
' window style 0 starts pwsh with its console already hidden, so nothing ever flashes on screen.
Dim sh, fso, ps1
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Show-ThemePicker.ps1")
sh.Run "pwsh -NoProfile -NoLogo -File """ & ps1 & """", 0, False
