# win-dotfiles login greeting.
# Renders a fastfetch system banner + a rotating tip on interactive shells. Numbered last so it is
# the final output before the first prompt. Opt out with `$env:WINDOTFILES_GREETING = 'off'`.
# Skipped automatically for non-interactive, redirected, and Codex shells.

if (-not $IsInteractiveShell -or $IsCodexShell) { return }
if ($env:WINDOTFILES_GREETING -and $env:WINDOTFILES_GREETING.ToLowerInvariant() -in 'off', '0', 'false', 'none') { return }

$WinDotfilesTips = @(
    'theme <name>  reskins everything (ashes, dracula, nord, mocha).'
    'project / proj  fuzzy-jump to any registered project.'
    'wmdev / wmbrowse  snap komorebi to a tuned layout for the active monitor.'
    'z <dir>  jumps with zoxide; ll / lt  list with icons + git status.'
    'winsmooth -Apply  re-applies workstation tuning; winsmooth  previews it.'
    'wincheck  audits the workstation; profileperf  times profile + prompt load.'
    'winharden  re-applies the AI/diagnostics hardening pass.'
    'Win+Arrows move windows; Alt+Shift+F toggles monocle in komorebi.'
)

function Show-WinDotfilesGreeting {
    $fastfetch = Get-Command fastfetch -ErrorAction SilentlyContinue
    if ($fastfetch) {
        $config = Join-Path $WinDotfilesRoot 'fastfetch\config.jsonc'
        $logo = Join-Path $WinDotfilesRoot 'fastfetch\logo.txt'
        $ffArgs = @()
        if (Test-Path -LiteralPath $config -PathType Leaf) { $ffArgs += @('--config', $config) }
        if (Test-Path -LiteralPath $logo -PathType Leaf) { $ffArgs += @('--logo-type', 'file', '--logo', $logo, '--logo-color-1', 'magenta') }
        & $fastfetch.Source @ffArgs
    }
    else {
        # Lightweight fallback when fastfetch is not installed.
        $theme = if (Test-Command Get-WinDotfilesActiveThemeName) { Get-WinDotfilesActiveThemeName } else { 'ashes' }
        Write-Host ''
        Write-Host '  ❯_ win·dotfiles' -ForegroundColor Magenta -NoNewline
        Write-Host "   $($env:USERNAME)@$($env:COMPUTERNAME)  ·  theme: $theme" -ForegroundColor DarkGray
    }

    # Rotating tip of the day.
    $tip = $WinDotfilesTips | Get-Random
    Write-Host ''
    Write-Host '  tip  ' -ForegroundColor Magenta -NoNewline
    Write-Host $tip -ForegroundColor DarkGray
    Write-Host ''
}

# Override `clear` (and its `cls` alias) so a cleared screen returns to the startup greeting
# instead of an empty prompt. `[char]27` sequences: 2J clears the screen, 3J clears scrollback,
# H homes the cursor. Falls back to the built-in clear if rendering the greeting fails.
function Clear-Host {
    $esc = [char]27
    [Console]::Write("$esc[2J$esc[3J$esc[H")
    try { Show-WinDotfilesGreeting } catch { Write-Verbose "Greeting skipped: $($_.Exception.Message)" }
}

try { Show-WinDotfilesGreeting } catch { Write-Verbose "Greeting skipped: $($_.Exception.Message)" }
