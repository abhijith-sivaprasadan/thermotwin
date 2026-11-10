# Open flagship drill-downs by posting clicks at cached tile locations, capturing each.
# Click coords are CLIENT coords = captured-image coords minus the window frame (~8, ~31).
param([string]$OutDir = (Join-Path $PSScriptRoot '..\build\gui-captures'))

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static void MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-4))) return; } catch {}
        try { SetProcessDPIAware(); } catch {}
    }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint nFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public static Bitmap Capture(IntPtr hwnd) {
        RECT r; GetWindowRect(hwnd, out r);
        int w = r.Right - r.Left; int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) return null;
        Bitmap bmp = new Bitmap(w, h);
        using (Graphics g = Graphics.FromImage(bmp)) { IntPtr hdc = g.GetHdc(); PrintWindow(hwnd, hdc, 2); g.ReleaseHdc(hdc); }
        return bmp;
    }
}
"@ -ReferencedAssemblies System.Drawing

[WinCap2]::MakeDpiAware()
$proc = Get-Process thermotwin-gui -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "NO_PROC"; exit 1 }
$hwnd = $proc.MainWindowHandle
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[WinCap2]::ShowWindow($hwnd, 9) | Out-Null
[WinCap2]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

$WM_LBUTTONDOWN = 0x0201; $WM_LBUTTONUP = 0x0202
function Click($cx, $cy) {
    $lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
    [WinCap2]::PostMessage($hwnd, $WM_LBUTTONDOWN, [IntPtr]1, $lp) | Out-Null
    Start-Sleep -Milliseconds 60
    [WinCap2]::PostMessage($hwnd, $WM_LBUTTONUP, [IntPtr]0, $lp) | Out-Null
    Start-Sleep -Milliseconds 750
}
function Cap($name) {
    $bmp = [WinCap2]::Capture($hwnd)
    if ($bmp) { $p = Join-Path $OutDir $name; $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output ("SAVED {0}" -f $p); $bmp.Dispose() }
    else { Write-Output "FAIL $name" }
}

# client = image - (8,31). CARBON card, P2X tile, health ring (estimated centers).
Click 1712 289;  Cap "fa_co2.png"
Click 742 1459;  Cap "fa_p2x.png"
Click 682 329;   Cap "fa_health.png"
