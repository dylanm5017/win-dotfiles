<#
.SYNOPSIS
    Waits for a Bluetooth headphone endpoint to appear and sets its Windows volume to a fixed level.
.DESCRIPTION
    The WH-1000XM6 shares a pairing key with a dual-booted Arch install. Bluetooth absolute volume
    stores the level on the headphones, so turning it down on Arch carries over to Windows as a
    lower endpoint volume. This runs at logon, polls until the endpoint is active, then resets it.

    Runs under Windows PowerShell 5.1: the MMDevice COM activation fails in pwsh 7
    (REGDB_E_CLASSNOTREG). Use -Register to create the per-user logon scheduled task.
#>
[CmdletBinding()]
param(
    [string]$DeviceMatch = 'WH-1000XM6',
    [ValidateRange(0, 100)][int]$Level = 100,
    [int]$TimeoutSeconds = 180,
    [switch]$Register
)

if ($Register) {
    $taskName = 'win-dotfiles Reset-HeadphoneVolume'
    $arguments = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" -DeviceMatch `"$DeviceMatch`" -Level $Level -TimeoutSeconds $TimeoutSeconds"
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "Registered scheduled task '$taskName'." -ForegroundColor Green
    return
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -DeviceMatch $DeviceMatch -Level $Level -TimeoutSeconds $TimeoutSeconds
    return
}

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection c); }
[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceCollection { int GetCount(out int n); int Item(int i, out IMMDevice d); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int a, out IPropertyStore s); }
[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore { int GetCount(out int c); int GetAt(int i, out PK k); int GetValue(ref PK k, out PV v); }
[StructLayout(LayoutKind.Sequential)] struct PK { public Guid f; public int p; }
[StructLayout(LayoutKind.Sequential)] struct PV { public short vt; short a, b, c; public IntPtr p; IntPtr q; }
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume { int R1(IntPtr a); int R2(IntPtr a); int GetChannelCount(out int c); int SetMasterVolumeLevel(float l, ref Guid g); int SetMasterVolumeLevelScalar(float l, ref Guid g); int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDE {}
public static class HeadphoneVolume {
  static string Name(IMMDevice d) { IPropertyStore s; d.OpenPropertyStore(0, out s); var k = new PK { f = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), p = 14 }; PV v; s.GetValue(ref k, out v); return Marshal.PtrToStringUni(v.p); }
  // Returns the volume (0-100) before the change, or -1 when no active render endpoint matches.
  public static int Set(string match, float level) {
    var e = (IMMDeviceEnumerator)new MMDE(); IMMDeviceCollection c; e.EnumAudioEndpoints(0, 1, out c); int n; c.GetCount(out n);
    for (int i = 0; i < n; i++) { IMMDevice d; c.Item(i, out d); if (!Name(d).Contains(match)) continue;
      var iid = typeof(IAudioEndpointVolume).GUID; object o; d.Activate(ref iid, 23, IntPtr.Zero, out o); var v = (IAudioEndpointVolume)o;
      float before; v.GetMasterVolumeLevelScalar(out before); var g = Guid.Empty; v.SetMasterVolumeLevelScalar(level, ref g);
      return (int)Math.Round(before * 100); }
    return -1; } }
'@

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $before = [HeadphoneVolume]::Set($DeviceMatch, $Level / 100)
    if ($before -ge 0) {
        Write-Output "$DeviceMatch volume $before% -> $Level%"
        return
    }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)

Write-Output "$DeviceMatch not connected within $TimeoutSeconds s; volume unchanged."
