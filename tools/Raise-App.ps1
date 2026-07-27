#requires -Version 5.1
<#
.SYNOPSIS
    Raise an app's window if it is already open, otherwise launch it.

.DESCRIPTION
    The Windows counterpart to a Hyprland raise-or-launch dispatcher: `Raise-App.ps1 browser`
    focuses the Chrome window you already have rather than starting a second one, and only
    launches when nothing matches.

    Windows are discovered through `komorebic state`, which lists every managed window with its
    hwnd/exe/title alongside the monitor, workspace, container and stack slot holding it. That
    positional detail is what makes a cross-workspace raise work at all: komorebi hides the
    windows of inactive workspaces, so the workspace has to be focused before the window can be
    brought to the foreground, and a window buried in a stack has to be surfaced with
    `focus-stack-window` rather than by handle. Without komorebi running it falls back to
    Get-Process main windows, which only sees one window per process.

    Repeat invocations cycle. Matches are ordered by (monitor, workspace, container, stack index)
    so the order is stable between runs, and the window *after* the current foreground one is
    picked, wrapping at the end.

    Two constraints come from whkd, which pipes bindings into a single long-lived
    `powershell -Command -` session: this has to stay Windows PowerShell 5.1 compatible and free
    of profile dependencies, but it also means the interop type below is compiled once per whkd
    session instead of once per keypress -- leaving `komorebic state` (~50 ms) as the real
    per-press cost.

    The app registry lives in powershell/apps.json, with an optional gitignored
    powershell/apps.local.json merged over it for machine-specific entries.

.EXAMPLE
    Raise-App.ps1 browser

.EXAMPLE
    Raise-App.ps1 -Exe wezterm-gui.exe -Title 'win-dotfiles' -Launch wezterm-gui.exe

.EXAMPLE
    Raise-App.ps1 -List
#>
[CmdletBinding()]
param(
    # Registry entry to raise: a name, one of its aliases, or an unambiguous prefix of either.
    [Parameter(Position = 0)]
    [string]$App,

    # Match windows by executable name instead of going through the registry.
    [string[]]$Exe,

    # Extra filter: only match windows whose title matches this regex.
    [string]$Title,

    # Command(s) to try when nothing matched; the first one that resolves wins.
    [string[]]$Launch,

    # Raise only -- never start the app.
    [switch]$NoLaunch,

    # Always raise the first match instead of cycling to the next one.
    [switch]$NoCycle,

    # Print the app registry and exit.
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not ('WinDotfiles.RaiseNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WinDotfiles
{
    public static class RaiseNative
    {
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool altTab);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
        [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
        [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

        private const int SW_RESTORE = 9;

        // Windows only lets the process that currently owns the foreground give it away, so a
        // bare SetForegroundWindow from a background script flashes the taskbar button instead
        // of switching. Borrowing the foreground thread's input queue for the duration of the
        // call makes us count as that owner; SwitchToThisWindow is the fallback alt-tab uses.
        public static bool Activate(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) { return false; }
            if (IsIconic(hWnd)) { ShowWindow(hWnd, SW_RESTORE); }

            uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
            uint currentThread = GetCurrentThreadId();
            bool attached = foregroundThread != 0
                && foregroundThread != currentThread
                && AttachThreadInput(currentThread, foregroundThread, true);
            try
            {
                SetForegroundWindow(hWnd);
            }
            finally
            {
                if (attached) { AttachThreadInput(currentThread, foregroundThread, false); }
            }

            if (GetForegroundWindow() != hWnd) { SwitchToThisWindow(hWnd, true); }
            return GetForegroundWindow() == hWnd;
        }
    }
}
'@
}

function ConvertTo-StringList {
    # @($null) is a one-element array holding $null, not an empty one, so an unbound [string[]]
    # parameter still reports Count 1 and quietly defeats a `.Count -eq 0` fallback test.
    param($Value)

    $list = New-Object System.Collections.ArrayList
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        [void]$list.Add($text)
    }

    , $list.ToArray()
}

function Get-AppRegistry {
    $entries = [ordered]@{}

    foreach ($leaf in @('apps.json', 'apps.local.json')) {
        $path = Join-Path $RepoRoot "powershell\$leaf"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        try {
            $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Ignoring $leaf (invalid JSON): $($_.Exception.Message)"
            continue
        }

        foreach ($app in @($document.apps)) {
            if (-not $app.name) { continue }
            # Merged over the committed set rather than replacing it, so apps.local.json only has
            # to carry the entries it actually changes.
            $entries[[string]$app.name] = $app
        }
    }

    $entries
}

function Resolve-AppEntry {
    param($Registry, [string]$Name)

    foreach ($key in $Registry.Keys) {
        if ($key -eq $Name) { return $Registry[$key] }
    }

    foreach ($key in $Registry.Keys) {
        foreach ($alias in @($Registry[$key].aliases)) {
            if ($alias -eq $Name) { return $Registry[$key] }
        }
    }

    # Unique prefix, so `raise brow` works while an ambiguous stem is refused rather than guessed.
    $matched = @()
    foreach ($key in $Registry.Keys) {
        if ($key.StartsWith($Name, [StringComparison]::OrdinalIgnoreCase)) { $matched += $Registry[$key] }
    }
    if ($matched.Count -eq 1) { return $matched[0] }
    if ($matched.Count -gt 1) {
        throw "'$Name' is ambiguous: $(($matched | ForEach-Object { $_.name }) -join ', ')"
    }

    $null
}

function New-RaiseWindow {
    param($Window, [int]$Monitor, [int]$Workspace, [int]$Container, [int]$StackIndex, [int]$StackSize, $VisibleHwnd)

    $handle = [IntPtr][int64]$Window.hwnd
    [pscustomobject]@{
        Hwnd        = $handle
        HwndValue   = [int64]$Window.hwnd
        Exe         = [string]$Window.exe
        Title       = [string]$Window.title
        Monitor     = $Monitor
        Workspace   = $Workspace
        Container   = $Container
        StackIndex  = $StackIndex
        StackSize   = $StackSize
        # The window the stack is currently showing. Equal to Hwnd unless this window is buried.
        VisibleHwnd = $VisibleHwnd
    }
}

function Get-KomorebiState {
    if (-not (Get-Process -Name komorebi -ErrorAction SilentlyContinue)) { return $null }

    try {
        $raw = & komorebic state 2>$null
    }
    catch {
        return $null
    }
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }

    try { return (($raw -join "`n") | ConvertFrom-Json) } catch { return $null }
}

function Get-KomorebiWindows {
    param($State)

    $windows = New-Object System.Collections.ArrayList
    $monitors = @($State.monitors.elements)

    for ($m = 0; $m -lt $monitors.Count; $m++) {
        $workspaces = @($monitors[$m].workspaces.elements)

        for ($w = 0; $w -lt $workspaces.Count; $w++) {
            $workspace = $workspaces[$w]

            # Everything on the workspace, flattened to one list of window rings. Tiled containers
            # come first; a monocled/maximized window sits outside the container ring, and floating
            # windows never enter it at all -- but all of them are raisable.
            $rings = New-Object System.Collections.ArrayList
            foreach ($container in @($workspace.containers.elements)) { [void]$rings.Add($container.windows) }
            if ($workspace.monocle_container) { [void]$rings.Add($workspace.monocle_container.windows) }
            if ($workspace.maximized_window) {
                [void]$rings.Add([pscustomobject]@{ elements = @($workspace.maximized_window); focused = 0 })
            }
            foreach ($floating in @($workspace.floating_windows.elements)) {
                [void]$rings.Add([pscustomobject]@{ elements = @($floating); focused = 0 })
            }

            for ($r = 0; $r -lt $rings.Count; $r++) {
                $elements = @($rings[$r].elements)
                if ($elements.Count -eq 0) { continue }

                $focusedIndex = 0
                if ($null -ne $rings[$r].focused) { $focusedIndex = [int]$rings[$r].focused }
                if ($focusedIndex -ge $elements.Count) { $focusedIndex = 0 }
                $visible = [IntPtr][int64]$elements[$focusedIndex].hwnd

                for ($i = 0; $i -lt $elements.Count; $i++) {
                    [void]$windows.Add((New-RaiseWindow -Window $elements[$i] -Monitor $m -Workspace $w `
                        -Container $r -StackIndex $i -StackSize $elements.Count -VisibleHwnd $visible))
                }
            }
        }
    }

    $windows
}

function Get-ProcessWindows {
    $windows = New-Object System.Collections.ArrayList

    foreach ($process in Get-Process) {
        if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
        # The desktop shell also runs as explorer.exe but carries no title; skipping untitled
        # windows keeps `raise files` from targeting it.
        if ([string]::IsNullOrWhiteSpace($process.MainWindowTitle)) { continue }

        [void]$windows.Add([pscustomobject]@{
            Hwnd        = $process.MainWindowHandle
            HwndValue   = [int64]$process.MainWindowHandle
            Exe         = "$($process.ProcessName).exe"
            Title       = $process.MainWindowTitle
            Monitor     = 0
            Workspace   = 0
            Container   = 0
            StackIndex  = 0
            StackSize   = 1
            VisibleHwnd = $process.MainWindowHandle
        })
    }

    $windows
}

function Start-AppCandidate {
    param([string[]]$Candidates)

    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        # Packaged (MSIX/Squirrel) apps have no stable path to launch -- explorer resolves the
        # AppsFolder ID for us, and it survives the per-version install directories they use.
        if ($candidate -like 'shell:*') {
            try {
                Start-Process -FilePath 'explorer.exe' -ArgumentList $candidate
                return $true
            }
            catch { continue }
        }

        $resolved = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) {
            try {
                Start-Process -FilePath $resolved.Source
                return $true
            }
            catch { continue }
        }

        # Last resort is ShellExecute, which honours the App Paths registry key -- that is how
        # chrome.exe, code.exe and ms-teams.exe resolve without ever being on PATH.
        try {
            Start-Process -FilePath $candidate
            return $true
        }
        catch { continue }
    }

    $false
}

$registry = Get-AppRegistry

if ($List) {
    $rows = foreach ($key in $registry.Keys) {
        $entry = $registry[$key]
        [pscustomobject]@{
            Name    = $entry.name
            Aliases = (@($entry.aliases) -join ', ')
            Exe     = (@($entry.exe) -join ', ')
            Launch  = (@($entry.launch) -join ', ')
        }
    }
    $rows | Format-Table -AutoSize
    return
}

$matchExe = ConvertTo-StringList $Exe
$matchTitle = $Title
$launchWith = ConvertTo-StringList $Launch
$label = if ($App) { $App } else { $matchExe -join ', ' }

if ($App) {
    $entry = Resolve-AppEntry -Registry $registry -Name $App
    if (-not $entry) {
        if ($matchExe.Count -eq 0) {
            # A bare exe name is a reasonable thing to type, so treat an unknown word that looks
            # like one as an ad-hoc match rather than an error.
            if ($App -like '*.exe') {
                $matchExe = @($App)
                if ($launchWith.Count -eq 0) { $launchWith = @($App) }
            }
            else {
                throw "Unknown app '$App'. Known: $(($registry.Keys) -join ', '). Add it to powershell/apps.local.json, or pass -Exe."
            }
        }
    }
    else {
        $label = [string]$entry.name
        if ($matchExe.Count -eq 0) { $matchExe = ConvertTo-StringList $entry.exe }
        if (-not $matchTitle) { $matchTitle = [string]$entry.title }
        if ($launchWith.Count -eq 0) { $launchWith = ConvertTo-StringList $entry.launch }
    }
}

if ($matchExe.Count -eq 0) {
    throw 'Nothing to match: pass an app name from the registry, or -Exe.'
}

$state = Get-KomorebiState
$candidates = if ($state) { Get-KomorebiWindows -State $state } else { Get-ProcessWindows }

# Not $matches: that is an automatic variable the -match below writes to.
$hits = @($candidates | Where-Object {
    $window = $_
    $exeHit = $false
    foreach ($name in $matchExe) {
        if ($window.Exe -eq $name) { $exeHit = $true; break }
    }
    $exeHit -and (-not $matchTitle -or $window.Title -match $matchTitle)
} | Sort-Object Monitor, Workspace, Container, StackIndex, HwndValue)

if ($hits.Count -eq 0) {
    if ($NoLaunch) {
        Write-Verbose "No window matched $label and -NoLaunch was set."
        return
    }
    if ($launchWith.Count -eq 0) {
        throw "No window matched '$label' and no launch command is configured for it."
    }
    if (-not (Start-AppCandidate -Candidates $launchWith)) {
        throw "No window matched '$label' and none of its launch commands resolved: $($launchWith -join ', ')"
    }
    Write-Verbose "Launched $label."
    return
}

# Cycling is just "the one after whatever is focused now". When the foreground window is not one
# of the matches -- the usual case -- that lands on the first, which is the plain raise.
$foreground = [int64][WinDotfiles.RaiseNative]::GetForegroundWindow()
Write-Verbose ("Matched {0}: {1} | foreground {2}" -f $label, (($hits | ForEach-Object { $_.HwndValue }) -join ', '), $foreground)

$target = $hits[0]
if (-not $NoCycle -and $hits.Count -gt 1) {
    for ($i = 0; $i -lt $hits.Count; $i++) {
        if ($hits[$i].HwndValue -eq $foreground) {
            $target = $hits[($i + 1) % $hits.Count]
            break
        }
    }
}

if ($state) {
    $monitors = @($state.monitors.elements)
    $focusedWorkspace = -1
    if ($target.Monitor -lt $monitors.Count) {
        $focusedWorkspace = [int]$monitors[$target.Monitor].workspaces.focused
    }

    if ($focusedWorkspace -ne $target.Workspace -or [int]$state.monitors.focused -ne $target.Monitor) {
        & komorebic focus-monitor-workspace $target.Monitor $target.Workspace 2>$null | Out-Null
        # komorebi unhides the workspace's windows asynchronously; without this the activation
        # below races it and lands on a window that is still hidden.
        Start-Sleep -Milliseconds 60
    }
}

if ($target.StackSize -gt 1 -and $target.VisibleHwnd -ne $target.Hwnd) {
    # Buried in a stack: only the showing window can take the foreground, so focus the stack
    # through it and let komorebi rotate the one we actually want into view.
    [void][WinDotfiles.RaiseNative]::Activate($target.VisibleHwnd)
    & komorebic focus-stack-window $target.StackIndex 2>$null | Out-Null
}
else {
    [void][WinDotfiles.RaiseNative]::Activate($target.Hwnd)
}

Write-Verbose "Raised $label -- $($target.Exe) '$($target.Title)' (monitor $($target.Monitor), workspace $($target.Workspace))"
