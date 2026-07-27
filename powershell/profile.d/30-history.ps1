if (Get-Module PSReadLine) {
    Set-PSReadLineOption -EditMode Windows

    # History hygiene: larger buffer, no duplicate entries, and keep secrets out of the saved file.
    try {
        Set-PSReadLineOption -MaximumHistoryCount 10000 -ErrorAction Stop
        Set-PSReadLineOption -HistoryNoDuplicates -ErrorAction Stop
    }
    catch {
        Write-Verbose "PSReadLine history options skipped: $($_.Exception.Message)"
    }

    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)

        # Accepted-line hook, so it doubles as this profile's "preexec": alias tips (65-alias-tips)
        # print between the typed line and its output. A tip must never break the prompt.
        try {
            Show-WinDotfilesAliasTip -Line $line
        }
        catch {
            Write-Verbose "Alias tip skipped: $($_.Exception.Message)"
        }

        # WezTerm's OSC 133 command-start mark + WEZTERM_CMD user var (47-wezterm). Defined only
        # inside WezTerm, so this is a no-op everywhere else.
        try {
            if ($global:WinDotfilesWezTerm) {
                Write-WinDotfilesWezExec -Line $line
            }
        }
        catch {
            Write-Verbose "WezTerm exec mark skipped: $($_.Exception.Message)"
        }

        if ($line -match '(?i)password|secret|token|apikey|api[_-]?key|connectionstring|-AsPlainText') {
            # Usable for the rest of the session, but never written to the history file.
            return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly
        }

        return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }

    if ($IsInteractiveShell) {
        try {
            # Plugin predictions (CompletionPredictor) when available, else history-only.
            $predictionSource = if (Get-Module -Name CompletionPredictor) { 'HistoryAndPlugin' } else { 'History' }
            Set-PSReadLineOption -PredictionSource $predictionSource -ErrorAction Stop
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop

            Set-PSReadLineOption -Colors @{
                InlinePrediction       = "`e[38;5;243m"  # muted grey, matches the Ashes palette
                ListPrediction         = "`e[38;5;246m"
                ListPredictionSelected = "`e[48;5;238m"
            } -ErrorAction Stop
        }
        catch {
            Write-Verbose "PSReadLine predictions skipped: $($_.Exception.Message)"
        }
    }
}
