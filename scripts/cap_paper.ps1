# Cycle the theme with T a given number of times, then capture the flagship.
param([int]$Presses = 3, [string]$OutFile = "fa_paper.png", [string]$OutDir = (Join-Path $PSScriptRoot '..\build\gui-captures'))
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public class WinCapT {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    public static void Dpi(){ try{ SetProcessDpiAwarenessContext((IntPtr)(-4)); }catch{} }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public static Bitmap Cap(IntPtr h){ RECT r; GetWindowRect(h, out r); int w=r.Right-r.Left, ht=r.Bottom-r.Top; if(w<=0||ht<=0) return null;
        Bitmap b=new Bitmap(w,ht); using(Graphics g=Graphics.FromImage(b)){ IntPtr dc=g.GetHdc(); PrintWindow(h,dc,2); g.ReleaseHdc(dc);} return b; }
}
"@ -ReferencedAssemblies System.Drawing
[WinCapT]::Dpi()
$p = Get-Process thermotwin-gui -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { "NO_PROC"; exit 1 }
$h = $p.MainWindowHandle
[WinCapT]::ShowWindow($h, 9) | Out-Null
[WinCapT]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
for ($i = 0; $i -lt $Presses; $i++) {
    [WinCapT]::PostMessage($h, 0x0100, [IntPtr]0x54, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 60
    [WinCapT]::PostMessage($h, 0x0101, [IntPtr]0x54, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 400
}
Start-Sleep -Milliseconds 400
$b = [WinCapT]::Cap($h)
if ($b) { $pp = Join-Path $OutDir $OutFile; $b.Save($pp, [System.Drawing.Imaging.ImageFormat]::Png); "SAVED $pp"; $b.Dispose() } else { "FAIL" }
