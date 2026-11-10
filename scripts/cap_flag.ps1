# DPI-aware capture of the flagship (F1 default) and detailed-overview (F1 toggle)
# plus a couple of regression tabs. Run via powershell.exe (needs System.Drawing).
param([string]$OutDir = (Join-Path $PSScriptRoot '..\build\gui-captures'))

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap {
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
        using (Graphics g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            PrintWindow(hwnd, hdc, 2);
            g.ReleaseHdc(hdc);
        }
        return bmp;
    }
}
"@ -ReferencedAssemblies System.Drawing

[WinCap]::MakeDpiAware()
$proc = Get-Process thermotwin-gui -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "NO_PROC"; exit 1 }
$hwnd = $proc.MainWindowHandle
if ($hwnd -eq 0) { Write-Output "NO_HWND"; exit 1 }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[WinCap]::ShowWindow($hwnd, 9) | Out-Null
[WinCap]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

function Cap($name) {
    $bmp = [WinCap]::Capture($hwnd)
    if ($bmp) {
        $p = Join-Path $OutDir $name
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output ("SAVED {0} {1}x{2}" -f $p, $bmp.Width, $bmp.Height)
        $bmp.Dispose()
    } else { Write-Output "FAIL $name" }
}
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
function Key($vk) {
    [WinCap]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 60
    [WinCap]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 750
}

# Fresh launch lands on the flagship (overview_detail = .false.)
Cap "fa_flagship.png"
Key 0x70                 # F1 -> toggle to detailed overview
Cap "fa_detail.png"
Key 0x70                 # F1 -> back to flagship
Cap "fa_flag2.png"
