if ($IsInteractiveShell -and (Get-Module PSReadLine)) {
    # fish/zsh-like completion menu on Tab.
    Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Shift+Tab -Function MenuComplete
}

if ($IsInteractiveShell -and (Get-Module PSReadLine) -and (Test-Command fzf -Application)) {
    Set-PSReadLineKeyHandler -Chord Ctrl+r -BriefDescription FzfHistory -LongDescription 'Search command history with fzf' -ScriptBlock {
        $selected = Invoke-FzfHistory
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }

    Set-PSReadLineKeyHandler -Chord Ctrl+t -BriefDescription FzfFiles -LongDescription 'Insert a file selected with fzf' -ScriptBlock {
        $selected = Invoke-FzfFile
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
}
