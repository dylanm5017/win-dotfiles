#Requires -Version 7
<#
.SYNOPSIS
    Live board of the Claude Code sessions on this machine: waiting on you, done, or working.
.DESCRIPTION
    Reads ~/.claude/sessions/<pid>.json, which each running session keeps current. That format is
    internal to Claude Code (seen on 2.1.329 and 2.1.330: status is busy, idle or waiting, plus
    waitingFor), so anything unrecognised shows as "unknown" instead of being guessed at.
    Read-only: it never writes to the session files or talks to a session.

    A file only counts while its process is alive with the recorded start time, so leftovers from a
    crash or a reused PID are dropped.
.PARAMETER Once
    Print one plain snapshot and exit.
.PARAMETER Raw
    Return the session objects instead of drawing.
.PARAMETER Dock
    Open the board in a strip at the top of the watch terminal (WezTerm --class wezterm-watch). Does
    nothing if a board is already open there. Set-SideDock.ps1 runs this when it starts that terminal.
.PARAMETER DockWaitSeconds
    With -Dock, keep trying this long for the terminal to come up.
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Raw,
    [switch]$Dock,
    [string]$Root = (Join-Path $HOME '.claude\sessions'),
    [ValidateRange(1, 60)][int]$IntervalSeconds = 2,
    [ValidateRange(4, 30)][int]$DockRows = 8,
    [int]$DockWaitSeconds = 0,
    [string]$DockSocket
)

$boardTitle = 'claude-agents'

function Get-ProjectName([string]$Cwd) {
    if (-not $Cwd) { return '?' }
    # A linked worktree reads as repo/worktree rather than as a project of its own.
    if ($Cwd -match '([^\\/]+)[\\/]\.(?:claude[\\/])?worktrees[\\/]([^\\/]+)') { return "$($Matches[1])/$($Matches[2])" }
    Split-Path -Leaf $Cwd
}

function Get-AgentSession {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $now = [DateTimeOffset]::UtcNow
    foreach ($file in [IO.Directory]::EnumerateFiles($Root, '*.json')) {
        # The session rewrites this file; a torn or vanished read is picked up on the next pass.
        try { $session = [IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { continue }
        if (-not $session.pid) { continue }

        $process = Get-Process -Id $session.pid -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        if ($session.procStart -and $process.StartTime.ToFileTimeUtc() -ne [long]$session.procStart) { continue }

        $since = if ($session.statusUpdatedAt) { $now - [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.statusUpdatedAt) } else { $null }
        $state = switch ($session.status) {
            'waiting' { 'waiting' }
            'idle' { 'done' }
            'busy' { 'working' }
            default { 'unknown' }
        }
        [PSCustomObject]@{
            State      = $state
            Since      = $since
            Project    = Get-ProjectName $session.cwd
            Name       = [string]$session.name
            WaitingFor = [string]$session.waitingFor
            Kind       = [string]$session.kind
            Pid        = $session.pid
        }
    }
}

function Format-Since($Span) {
    if ($null -eq $Span) { return '-' }
    if ($Span.TotalSeconds -lt 0) { return '0s' }
    if ($Span.TotalMinutes -lt 1) { return "$([int][math]::Floor($Span.TotalSeconds))s" }
    if ($Span.TotalHours -lt 1) { return "$([int][math]::Floor($Span.TotalMinutes))m" }
    if ($Span.TotalDays -lt 1) { return '{0}h{1:00}m' -f [int][math]::Floor($Span.TotalHours), $Span.Minutes }
    "$([int][math]::Floor($Span.TotalDays))d"
}

function Limit-Text([string]$Text, [int]$Width) {
    if ($Width -le 0) { return '' }
    # Session names are free text: strip control characters so one cannot emit escape sequences.
    $Text = $Text -replace '\p{C}', ' '
    if ($Text.Length -le $Width) { return $Text.PadRight($Width) }
    if ($Width -eq 1) { return '…' }
    $Text.Substring(0, $Width - 1) + '…'
}

function Get-BoardLine {
    param([object[]]$Sessions, [int]$Width, [int]$Height, [switch]$Color)

    $esc = [char]27
    $style = @{
        waiting = @{ Mark = '●'; Label = 'needs you'; Code = '1;33' }
        done    = @{ Mark = '✓'; Label = 'done'; Code = '32' }
        working = @{ Mark = '·'; Label = 'working'; Code = '36' }
        unknown = @{ Mark = '?'; Label = 'unknown'; Code = '90' }
    }
    $rank = @{ waiting = 0; done = 1; working = 2; unknown = 3 }
    function Paint($Text, $Code) { if ($Color) { "$esc[${Code}m$Text$esc[0m" } else { $Text } }

    # Oldest first while waiting (longest-blocked on top); most recent first otherwise.
    $sorted = @($Sessions | Sort-Object { $rank[$_.State] }, { $s = if ($_.Since) { $_.Since.TotalSeconds } else { 0 }; if ($_.State -eq 'waiting') { -$s } else { $s } })
    $counts = foreach ($state in 'waiting', 'done', 'working', 'unknown') {
        $n = @($sorted | Where-Object State -eq $state).Count
        if ($n) { Paint "$n $($style[$state].Label)" $style[$state].Code }
    }
    $header = (Paint 'agents' '1') + '  ' + $(if ($counts) { $counts -join '  ' } else { Paint 'no sessions running' '90' })
    $header

    $room = [math]::Max(1, $Height - 1)
    $shown = $sorted
    if ($sorted.Count -gt $room) { $shown = @($sorted | Select-Object -First ([math]::Max(0, $room - 1))) }
    foreach ($session in $shown) {
        $look = $style[$session.State]
        $detail = if ($session.State -eq 'waiting' -and $session.WaitingFor) { "$($session.WaitingFor): $($session.Name)" } else { $session.Name }
        $lead = " $($look.Mark) $($look.Label.PadRight(9)) $((Format-Since $session.Since).PadLeft(6))  "
        $project = Limit-Text $session.Project ([math]::Min(24, [math]::Max(0, $Width - $lead.Length)))
        $rest = Limit-Text $detail ($Width - $lead.Length - $project.Length - 2)
        (Paint $lead $look.Code) + $project + $(if ($rest) { '  ' + (Paint $rest '90') })
    }
    if ($shown.Count -lt $sorted.Count) { Paint " +$($sorted.Count - $shown.Count) more" '90' }
}

if ($Dock) {
    $wezterm = Get-Command wezterm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wezterm) { throw 'wezterm is not on PATH.' }
    $saved = $env:WEZTERM_UNIX_SOCKET
    $deadline = (Get-Date).AddSeconds($DockWaitSeconds)
    try {
        $panes = @()
        while ($true) {
            # The scoop shim and the real GUI share a command line; only the real one owns a socket.
            $socket = if ($DockSocket) { $DockSocket } else {
                Get-CimInstance Win32_Process -Filter "Name='wezterm-gui.exe'" |
                    Where-Object { $_.CommandLine -match '--class\s+"?wezterm-watch' } |
                    ForEach-Object { Join-Path $HOME ".local\share\wezterm\gui-sock-$($_.ProcessId)" } |
                    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            }
            if ($socket) {
                $env:WEZTERM_UNIX_SOCKET = $socket
                $listing = & $wezterm.Source cli --no-auto-start list --format json 2>$null
                if ($LASTEXITCODE -eq 0) { $panes = @($listing | ConvertFrom-Json) }
            }
            if ($panes) { break }
            if ((Get-Date) -ge $deadline) { throw 'The watch terminal is not running (Alt+8 opens it).' }
            Start-Sleep -Seconds 1
        }
        if ($panes | Where-Object { $_.title -eq $boardTitle }) {
            Write-Host 'The agent board is already open in the watch terminal.'
            return
        }
        $target = @($panes | Sort-Object { -not $_.is_active }, pane_id)[0]
        $paneId = & $wezterm.Source cli split-pane --pane-id $target.pane_id --top-level --top --cells $DockRows -- pwsh.exe -NoLogo -NoProfile -File $PSCommandPath
        if ($LASTEXITCODE -ne 0) { throw 'Could not split the watch terminal.' }
        & $wezterm.Source cli activate-pane --pane-id $target.pane_id
        Write-Host "Agent board opened (pane $paneId)."
    }
    finally {
        $env:WEZTERM_UNIX_SOCKET = $saved
    }
    return
}

if ($Raw) { return Get-AgentSession }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
if ($Once) { return Get-BoardLine -Sessions @(Get-AgentSession) -Width 100 -Height 100 }

$esc = [char]27
[Console]::Title = $boardTitle
try {
    [Console]::Write("$esc]2;$boardTitle`a$esc[?25l$esc[2J")
    while ($true) {
        # The last column stays free so a full-width row never wraps.
        $lines = @(Get-BoardLine -Sessions @(Get-AgentSession) -Width ([Console]::WindowWidth - 1) -Height ([Console]::WindowHeight) -Color)
        [Console]::Write("$esc[H" + (($lines | ForEach-Object { "$_$esc[K" }) -join "`r`n") + "$esc[J")
        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    [Console]::Write("$esc[?25h$esc[0m`r`n")
}
