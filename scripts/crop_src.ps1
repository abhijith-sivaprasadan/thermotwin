# Crop a region from any PNG (full source path) for detailed inspection.
# Run via powershell.exe (needs System.Drawing).
param(
    [string] $Src,
    [int] $X, [int] $Y, [int] $W, [int] $H,
    [string] $Out = "crop.png",
    [double] $Scale = 1.0
)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Src)
$W = [Math]::Min($W, $img.Width - $X)
$H = [Math]::Min($H, $img.Height - $Y)
$rect = New-Object System.Drawing.Rectangle($X, $Y, $W, $H)
$crop = ($img -as [System.Drawing.Bitmap]).Clone($rect, $img.PixelFormat)
$ow = [int]($W * $Scale); $oh = [int]($H * $Scale)
$dst = New-Object System.Drawing.Bitmap($ow, $oh)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($crop, 0, 0, $ow, $oh)
$g.Dispose()
$outpath = Join-Path (Join-Path $PSScriptRoot '..\build\gui-captures') $Out
$dst.Save($outpath, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose(); $crop.Dispose(); $dst.Dispose()
Write-Output ("CROP {0} {1}x{2}" -f $outpath, $ow, $oh)
