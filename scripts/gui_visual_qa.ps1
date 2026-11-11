$ErrorActionPreference = "Stop"
$folder = Join-Path $PWD "build/gui-visual-qa"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$env:THERMOTWIN_GUI_VISUAL_QA = "1"
$binary = Join-Path $PWD "thermotwin-gui-offline.exe"
if (!(Test-Path $binary)) { throw "Offline GUI binary absent" }
Write-Host "Starting real Win32 GUI capture in Windows runner desktop"
$proc = Start-Process -FilePath $binary -WorkingDirectory $PWD -PassThru
if (!$proc.WaitForExit(25000)) {
    Stop-Process -Id $proc.Id -Force
    throw "Native GUI screenshot harness exceeded 25 seconds; runner may not have interactive desktop"
}
Write-Host ("Win32 GUI process exit code: " + $proc.ExitCode)
$expected = @("01-overview.png","02-turbine.png","03-alarms.png")
Add-Type -AssemblyName System.Drawing
foreach ($name in $expected) {
    $path = Join-Path $folder $name
    if (!(Test-Path $path)) { throw "Missing native screenshot: $name" }
    $img = [System.Drawing.Image]::FromFile($path)
    try {
        if ($img.Width -lt 1024 -or $img.Height -lt 720) { throw "Invalid screenshot resolution: $name" }
        Write-Host ("Native screenshot {0}: {1}x{2} px; {3} bytes" -f $name, $img.Width, $img.Height, (Get-Item $path).Length)
        {
            $newWidth = 800
            $newHeight = [int][Math]::Round($img.Height * $newWidth / $img.Width)
            $thumb = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
            $g = [System.Drawing.Graphics]::FromImage($thumb)
            try { $g.DrawImage($img, 0, 0, $newWidth, $newHeight) }
            finally { $g.Dispose() }
            $out = Join-Path $folder ($name -replace "\.png$", "-thumb.jpg")
            $thumb.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $thumb.Dispose()
            $tag = ($name -replace "\.png$", "").ToUpperInvariant() -replace "^[0-9]+-", ""
            Write-Host ("HMI_" + $tag + "_JPEG_BASE64:" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($out)))
        }
    }
    finally { $img.Dispose() }
}
