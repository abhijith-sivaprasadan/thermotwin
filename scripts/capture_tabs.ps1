# Capture each HMI tab of the running thermotwin-gui window to a PNG via PrintWindow.
# Switches tabs by posting WM_KEYDOWN/WM_KEYUP for VK_F1..VK_F15 directly to the hwnd.
param(
    [int[]] $Screens = (1..15),
    [string] $OutDir = "C:\Users\prasa\Downloads\tt_caps"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static void MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-4))) return; } catch {}  // PER_MONITOR_AWARE_V2
        try { SetProcessDPIAware(); } catch {}
    }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint nFlags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT lpRect);
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
            PrintWindow(hwnd, hdc, 2); // PW_RENDERFULLCONTENT
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
[WinCap]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
[WinCap]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101
foreach ($s in $Screens) {
    $vk = 0x6F + $s   # VK_F1 = 0x70 => screen 1
    [WinCap]::PostMessage($hwnd, $WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 60
    [WinCap]::PostMessage($hwnd, $WM_KEYUP, [IntPtr]$vk, [IntPtr]0) | Out-Null
    Start-Sleep -Milliseconds 650   # allow repaint (WM_TIMER repaints ~250ms)
    $bmp = [WinCap]::Capture($hwnd)
    if ($bmp) {
        $path = Join-Path $OutDir ("tab{0:00}.png" -f $s)
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Output ("SAVED {0} {1}x{2}" -f $path, $bmp.Width, $bmp.Height)
    } else {
        Write-Output ("FAIL screen {0}" -f $s)
    }
}
