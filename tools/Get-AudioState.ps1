<#
.SYNOPSIS
    Reports the active playback endpoints, their volumes and the Windows default outputs as JSON.
.DESCRIPTION
    Runs under Windows PowerShell 5.1: the MMDevice COM activation fails in pwsh 7
    (REGDB_E_CLASSNOTREG), so pwsh re-launches this and parses the JSON. audiocheck and audiofix
    (powershell/profile.d/152-audio.ps1) are the callers.
.PARAMETER SetLevel
    Set the volume (0-100) of the first active endpoint whose name contains -DeviceMatch, and unmute it.
.PARAMETER SetDefault
    Make the first active endpoint whose name contains -DeviceMatch the default for the console and
    multimedia roles. The communications default is left alone.
#>
[CmdletBinding()]
param(
    [string]$DeviceMatch,
    [ValidateRange(0, 100)][int]$SetLevel = 100,
    [switch]$SetDefault
)

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $forward = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) { if ($value) { $forward += "-$key" } }
        else { $forward += "-$key", "$value" }
    }
    & powershell.exe @forward
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace WinDotfiles {
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection c); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceCollection { int GetCount(out int n); int Item(int i, out IMMDevice d); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int a, out IPropertyStore s); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }
[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore { int GetCount(out int c); int GetAt(int i, out PK k); int GetValue(ref PK k, out PV v); }
[StructLayout(LayoutKind.Sequential)] struct PK { public Guid f; public int p; }
[StructLayout(LayoutKind.Sequential)] struct PV { public short vt; short a, b, c; public IntPtr p; IntPtr q; }
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume { int R1(IntPtr a); int R2(IntPtr a); int GetChannelCount(out int c); int SetMasterVolumeLevel(float l, ref Guid g); int SetMasterVolumeLevelScalar(float l, ref Guid g); int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l); int SetChannelVolumeLevel(int n, float l, ref Guid g); int SetChannelVolumeLevelScalar(int n, float l, ref Guid g); int GetChannelVolumeLevel(int n, out float l); int GetChannelVolumeLevelScalar(int n, out float l); int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid g); int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m); }
[Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig { int R1(); int R2(); int R3(); int R4(); int R5(); int R6(); int R7(); int R8(); int R9(); int R10(); [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDE {}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfig {}
public class Endpoint { public string Name, Id; public int Volume; public bool Muted, DefaultConsole, DefaultMultimedia, DefaultCommunications; }
public static class Audio {
  static string Name(IMMDevice d) { IPropertyStore s; d.OpenPropertyStore(0, out s); var k = new PK { f = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), p = 14 }; PV v; s.GetValue(ref k, out v); return Marshal.PtrToStringUni(v.p); }
  static IAudioEndpointVolume Vol(IMMDevice d) { var iid = typeof(IAudioEndpointVolume).GUID; object o; d.Activate(ref iid, 23, IntPtr.Zero, out o); return (IAudioEndpointVolume)o; }
  static string DefaultId(IMMDeviceEnumerator e, int role) { IMMDevice d; if (e.GetDefaultAudioEndpoint(0, role, out d) != 0 || d == null) return null; string id; d.GetId(out id); return id; }
  public static List<Endpoint> List() {
    var e = (IMMDeviceEnumerator)new MMDE(); string c0 = DefaultId(e, 0), m0 = DefaultId(e, 1), k0 = DefaultId(e, 2);
    IMMDeviceCollection c; e.EnumAudioEndpoints(0, 1, out c); int n; c.GetCount(out n); var r = new List<Endpoint>();
    for (int i = 0; i < n; i++) { IMMDevice d; c.Item(i, out d); string id; d.GetId(out id); var v = Vol(d); float l; v.GetMasterVolumeLevelScalar(out l); bool m; v.GetMute(out m);
      r.Add(new Endpoint { Name = Name(d), Id = id, Volume = (int)Math.Round(l * 100), Muted = m, DefaultConsole = id == c0, DefaultMultimedia = id == m0, DefaultCommunications = id == k0 }); }
    return r; }
  public static void SetLevel(string id, int level) {
    var e = (IMMDeviceEnumerator)new MMDE(); IMMDeviceCollection c; e.EnumAudioEndpoints(0, 1, out c); int n; c.GetCount(out n);
    for (int i = 0; i < n; i++) { IMMDevice d; c.Item(i, out d); string x; d.GetId(out x); if (x != id) continue; var v = Vol(d); var g = Guid.Empty; v.SetMasterVolumeLevelScalar(level / 100f, ref g); v.SetMute(false, ref g); } }
  public static int SetDefault(string id) { var p = (IPolicyConfig)new PolicyConfig(); int a = p.SetDefaultEndpoint(id, 0), b = p.SetDefaultEndpoint(id, 1); return a != 0 ? a : b; }
} }
'@

if ($DeviceMatch) {
    $target = [WinDotfiles.Audio]::List() | Where-Object { $_.Name.Contains($DeviceMatch) } | Select-Object -First 1
    if (-not $target) { throw "No active playback endpoint matches '$DeviceMatch'." }
    if ($PSBoundParameters.ContainsKey('SetLevel')) { [WinDotfiles.Audio]::SetLevel($target.Id, $SetLevel) }
    if ($SetDefault) {
        $hr = [WinDotfiles.Audio]::SetDefault($target.Id)
        if ($hr -ne 0) { throw ('SetDefaultEndpoint failed: 0x{0:X8}' -f $hr) }
    }
}

ConvertTo-Json -InputObject @([WinDotfiles.Audio]::List()) -Depth 3 -Compress
