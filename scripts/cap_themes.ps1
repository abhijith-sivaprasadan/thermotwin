# DPI-aware capture of the new themes by posting the T key to cycle.
# Order from launch (Blueprint): T->ClassicDK, T->ClassicLT, T->Paper, T->Aurora, T->Glass, T->Hicon
param([string]$OutDir = (Join-Path $PSScriptRoot '..\build\gui-captures'))

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCapT {
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

[WinCapT]::MakeDpiAware()
$proc = Get-Process thermotwin-gui -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "NO_PROC"; exit 1 }
$hwnd = $proc.MainWindowHandle
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[WinCapT]::ShowWindow($hwnd, 9) | Out-Null
[WinCapT]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101; $VK_T = 0x54
function T() {
    [WinCapT]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$VK_T, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 60
    [WinCapT]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$VK_T, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 700
}
function Cap($name) {
    $bmp = [WinCapT]::Capture($hwnd)
    if ($bmp) { $p = Join-Path $OutDir $name; $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output ("SAVED {0}" -f $p); $bmp.Dispose() }
    else { Write-Output "FAIL $name" }
}

T; T; T; T          # -> Aurora (theme 4)
Cap "th_aurora.png"
T                   # -> Glass (theme 5)
Cap "th_glass.png"
T                   # -> Hicon (theme 6)
Cap "th_hicon.png"
