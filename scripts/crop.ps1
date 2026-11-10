# Crop a region from a captured tab PNG for detailed inspection.
# Usage: crop.ps1 -Tab 1 -X 1300 -Y 150 -W 1260 -H 260 [-Out name.png] [-Scale 1.0]
param(
    [int] $Tab,
    [int] $X, [int] $Y, [int] $W, [int] $H,
    [string] $Out = "crop.png",
    [double] $Scale = 1.0
)
Add-Type -AssemblyName System.Drawing
$src = "C:\Users\prasa\Downloads\tt_caps\tab{0:00}.png" -f $Tab
$img = [System.Drawing.Image]::FromFile($src)
$W = [Math]::Min($W, $img.Width - $X)
$H = [Math]::Min($H, $img.Height - $Y)
$rect = New-Object System.Drawing.Rectangle($X, $Y, $W, $H)
$crop = ($img -as [System.Drawing.Bitmap]).Clone($rect, $img.PixelFormat)
$ow = [int]($W * $Scale); $oh = [int]($H * $Scale)
$dst = New-Object System.Drawing.Bitmap($ow, $oh)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.DrawImage($crop, 0, 0, $ow, $oh)
$g.Dispose()
$outpath = Join-Path "C:\Users\prasa\Downloads\tt_caps" $Out
$dst.Save($outpath, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose(); $crop.Dispose(); $dst.Dispose()
Write-Output ("CROP {0} {1}x{2}" -f $outpath, $ow, $oh)
