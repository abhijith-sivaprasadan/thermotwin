$ErrorActionPreference = "Stop"
$folder = Join-Path $PWD "build/gui-visual-qa"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$env:THERMOTWIN_GUI_VISUAL_QA = "1"
$binary = Join-Path $PWD "thermotwin-gui-offline.exe"
if (!(Test-Path $binary)) { throw "Expected original offline GUI executable absent" }
$proc = Start-Process -FilePath $binary -WorkingDirectory $PWD -PassThru
if (!$proc.WaitForExit(25000)) {
    Stop-Process -Id $proc.Id -Force
    throw "Original GUI screenshot harness timed out; graphical desktop unavailable"
}
Write-Host ("Original GUI exited code " + $proc.ExitCode)
$expected = @(
"01-original-overview.png","01-original-overview-1536.png",
"02-original-turbine.png","02-original-turbine-1536.png",
"03-original-alarms.png","03-original-alarms-1536.png",
"04-original-alarms-stress.png","04-original-alarms-stress-1536.png",
"05-controls-bottom.png","05-controls-bottom-1536.png",
"06-equipment.png","06-equipment-1536.png",
"07-trip-sequence.png","07-trip-sequence-1536.png",
"08-trip-events.png","08-trip-events-1536.png")
Add-Type -AssemblyName System.Drawing
foreach($name in $expected) {
    $path = Join-Path $folder $name
    if (!(Test-Path $path)) { throw "Native original HMI screenshot missing: $name" }
    $img=[System.Drawing.Image]::FromFile($path)
    try {
        if ($img.Width -lt 1024 -or $img.Height -lt 720) {
            throw "Unexpected native original HMI resolution: $name"
        }
        Write-Host ("Original HMI screenshot {0}: {1}x{2} px; {3} bytes" -f $name,$img.Width,$img.Height,(Get-Item $path).Length)
        $newWidth = 800
        $newHeight = [int][Math]::Round($img.Height*$newWidth/$img.Width)
        $thumb = New-Object System.Drawing.Bitmap($newWidth,$newHeight)
        $g = [System.Drawing.Graphics]::FromImage($thumb)
        try { $g.DrawImage($img,0,0,$newWidth,$newHeight) }
        finally { $g.Dispose() }
        $out = Join-Path $folder ($name -replace "\.png$","-thumb.jpg")
        $thumb.Save($out,[System.Drawing.Imaging.ImageFormat]::Jpeg)
        $thumb.Dispose()
        $tag = ($name -replace "\.png$","").ToUpperInvariant() -replace "^[0-9]+-",""
        Write-Host ("HMI_" + $tag + "_JPEG_BASE64:" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($out)))
    } finally { $img.Dispose() }
}
