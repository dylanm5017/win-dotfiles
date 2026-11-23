<#
.SYNOPSIS
    Docks the always-up side apps into the reserved strip on the far-left edge of the ultrawide.
.DESCRIPTION
    komorebi ignores these windows (ignore_rules) and the ultrawide's work_area_offset keeps tiles
    out of its left strip, so they stay visible on every workspace without being tiled. Layout,
    left to right (the far edge is the hardest to look at, so the least-read apps go there):

        | YouTube Music (top) |  watch   | tiles ...
        | Wave Link (bottom)  | terminal |

    The watch terminal is a WezTerm window started with `--class wezterm-watch`, which is how
    komorebi and this script tell it apart from ordinary WezTerm windows.

    The geometry mirrors komorebi.json: MediaWidth + WatchWidth must equal the ultrawide's
    work_area_offset.left, Top matches the bar reservation, and Padding (workspace padding +
    container padding + border, measured at 15px) lines the dock up with the tile edges.
.PARAMETER Launch
    Start any slot whose app is not running, then wait for its window.
.PARAMETER SkipLaunch
    Slots that -Launch must not start; they are still docked if already open.
.PARAMETER Focus
    Bring this slot's window to the foreground after docking (launching it first if needed).
.PARAMETER Register
    Create the per-user logon scheduled task that runs this with -Launch shortly after sign-in.
#>
[CmdletBinding()]
param(
    [int]$MediaWidth = 1280,
    [int]$WatchWidth = 1024,
    [ValidateRange(0.1, 0.9)][double]$MusicShare = 0.6,
    [int]$Padding = 15,
    [int]$Gap = 14,
    [int]$Top = 42,
    [int]$TimeoutSeconds = 30,
    [switch]$Launch,
    [string[]]$SkipLaunch = @(),
    [ValidateSet('music', 'wavelink', 'watch')][string]$Focus,
    [switch]$Register
)

if ($Register) {
    $taskName = 'win-dotfiles Set-SideDock'
    $arguments = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Launch -SkipLaunch wavelink -TimeoutSeconds 90"
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    # Give autostarted apps a head start so -Launch doesn't race them. Start-WaveLink.ps1 owns Wave Link.
    $trigger.Delay = 'PT20S'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "Registered scheduled task '$taskName'." -ForegroundColor Green
    return
}

Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
namespace WinDotfiles {
public static class SideDock {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    // Titled, unowned top-level windows of the given processes and/or with the given class.
    public static List<IntPtr> Find(uint[] pids, string cls) {
        var set = new HashSet<uint>(pids); var found = new List<IntPtr>();
        EnumWindows((h, l) => {
            if (GetWindow(h, 4) != IntPtr.Zero || GetWindowTextLength(h) == 0) return true;
            if (!string.IsNullOrEmpty(cls)) {
                var sb = new StringBuilder(256); GetClassName(h, sb, 256);
                if (sb.ToString() != cls) return true;
            }
            if (set.Count > 0) { uint pid; GetWindowThreadProcessId(h, out pid); if (!set.Contains(pid)) return true; }
            found.Add(h); return true;
        }, IntPtr.Zero);
        return found;
    }

    // Targets the visible frame: DWM's extended bounds exclude the invisible resize border.
    public static void Place(IntPtr h, int x, int y, int w, int hgt) {
        if (IsIconic(h) || !IsWindowVisible(h)) ShowWindow(h, 9);
        RECT win, vis; GetWindowRect(h, out win);
        if (DwmGetWindowAttribute(h, 9, out vis, Marshal.SizeOf(typeof(RECT))) != 0) vis = win;
        int l = vis.Left - win.Left, t = vis.Top - win.Top, r = win.Right - vis.Right, b = win.Bottom - vis.Bottom;
        SetWindowPos(h, IntPtr.Zero, x - l, y - t, w + l + r, hgt + t + b, 0x0014);
    }

    public static void Activate(IntPtr h) {
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(h);
    }
}
}
'@

$slots = [ordered]@{
    music    = @{ Exe = @('youtube-music-desktop-app', 'Spotify'); Class = $null
                  Launch = { & (Join-Path $PSScriptRoot 'Raise-App.ps1') music } }
    wavelink = @{ Exe = @('Elgato.WaveLink'); Class = $null
                  Launch = { Start-Process 'shell:AppsFolder\Elgato.WaveLink_g54w8ztgkx496!App' } }
    watch    = @{ Exe = @(); Class = 'wezterm-watch'
                  Launch = { Start-Process wezterm-gui.exe -ArgumentList 'start', '--class', 'wezterm-watch' } }
}

function Get-SlotWindow($slot) {
    $pids = [uint32[]]@()
    if ($slot.Exe.Count -gt 0) {
        $pids = [uint32[]]@(Get-Process -Name $slot.Exe -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        if ($pids.Count -eq 0) { return $null }
    }
    @([WinDotfiles.SideDock]::Find($pids, $slot.Class) |
        Sort-Object { -not [WinDotfiles.SideDock]::IsWindowVisible($_) }) | Select-Object -First 1
}

Add-Type -AssemblyName System.Windows.Forms
$screens = @([System.Windows.Forms.Screen]::AllScreens)
$ultrawide = $screens | Sort-Object { $_.Bounds.Width } -Descending | Select-Object -First 1
if ($screens.Count -lt 2 -or $ultrawide.Primary) {
    Write-Verbose 'No secondary ultrawide connected; leaving the side apps where they are.'
    return
}

$b = $ultrawide.Bounds
$half = [int]($Gap / 2)
$y0 = $b.Top + $Top + $Padding
$y1 = $b.Bottom - $Padding
$mediaX0 = $b.Left + $Padding
$mediaX1 = $b.Left + $MediaWidth - $half
$watchX0 = $b.Left + $MediaWidth + $half
$watchX1 = $b.Left + $MediaWidth + $WatchWidth - $Gap + $Padding
$split = $y0 + [int](($y1 - $y0 - $Gap) * $MusicShare)

$rects = @{
    music    = @($mediaX0, $y0, ($mediaX1 - $mediaX0), ($split - $y0))
    wavelink = @($mediaX0, ($split + $Gap), ($mediaX1 - $mediaX0), ($y1 - $split - $Gap))
    watch    = @($watchX0, $y0, ($watchX1 - $watchX0), ($y1 - $y0))
}

$launched = $false
foreach ($name in $slots.Keys) {
    $slot = $slots[$name]
    if (-not (Get-SlotWindow $slot) -and (($Launch -and $name -notin $SkipLaunch) -or $Focus -eq $name)) {
        & $slot.Launch
        $launched = $true
    }
}

foreach ($name in $slots.Keys) {
    $slot = $slots[$name]
    $window = Get-SlotWindow $slot
    if ($launched -and -not $window -and $name -notin $SkipLaunch) {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not $window -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $window = Get-SlotWindow $slot
        }
        # Electron restores its saved bounds just after the window appears; dock after that settles.
        if ($window) { Start-Sleep -Milliseconds 1500 }
    }
    if (-not $window) {
        Write-Verbose "No $name window found."
        continue
    }
    $r = $rects[$name]
    [WinDotfiles.SideDock]::Place($window, $r[0], $r[1], $r[2], $r[3])
    Write-Verbose "Docked $name ($window) at $($r[0]),$($r[1]) $($r[2])x$($r[3])."
}

if ($Focus) {
    $window = Get-SlotWindow $slots[$Focus]
    if ($window) { [WinDotfiles.SideDock]::Activate($window) }
}
