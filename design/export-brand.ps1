#requires -Version 7.0
# Run on Windows. GDI+ exports the approved raster artwork without installing fonts.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $root 'assets/brand'
$icons = Join-Path $PSScriptRoot 'exports/icons'
$windows = Join-Path $root 'windows/runner/resources'
foreach ($dir in @($assets, $icons)) { $null = [IO.Directory]::CreateDirectory($dir) }
$board = [Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'references/beastemu_identidade_visual.png.png'))
$original = [Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'references/beastemu_emblema_original.png.png'))
if ($board.Width -ne 1536 -or $board.Height -ne 1024) { throw 'Dimensões da prancha inesperadas.' }

function Canvas([int]$w, [int]$h) { [Drawing.Bitmap]::new($w, $h) }
function Paint($canvas, $image, [int]$x, [int]$y, [int]$w, [int]$h) {
    $g = [Drawing.Graphics]::FromImage($canvas)
    try {
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.PixelOffsetMode = 'Half'
        $g.DrawImage($image, [Drawing.Rectangle]::new($x, $y, $w, $h), 0, 0, $image.Width, $image.Height, [Drawing.GraphicsUnit]::Pixel)
    } finally { $g.Dispose() }
}
function Crop([int]$x, [int]$y, [int]$w, [int]$h) {
    $board.Clone([Drawing.Rectangle]::new($x,$y,$w,$h), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
}
function Cut-Lettering($bitmap) {
    # Remove the near-black photographic backdrop while retaining red and silver edges.
    for ($y = 0; $y -lt $bitmap.Height; $y++) {
        for ($x = 0; $x -lt $bitmap.Width; $x++) {
            $c = $bitmap.GetPixel($x,$y)
            $signal = [Math]::Max($c.G - 9, ($c.R - 38) * 0.7)
            $alpha = [int]([Math]::Clamp($signal / 23, 0, 1) * $c.A)
            $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($alpha,$c.R,$c.G,$c.B))
        }
    }
}
function Save-Png($bitmap, $path) { $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png) }

$crest = Crop 78 819 184 169
$word = Crop 302 861 519 86
Cut-Lettering $crest
Cut-Lettering $word
$horizontal = Canvas 666 128
Paint $horizontal $crest 1 2 134 123
Paint $horizontal $word 146 22 519 86
Save-Png $horizontal (Join-Path $assets 'logo-horizontal.png')
$compact = Canvas 276 190
Paint $compact $crest 63 1 150 138
Paint $compact $word 1 144 274 45
Save-Png $compact (Join-Path $assets 'logo-compact.png')
Save-Png $crest (Join-Path $assets 'symbol.png')
$emblem = Canvas 384 384
Paint $emblem $original 0 0 384 384
Save-Png $emblem (Join-Path $assets 'emblem.png')

# The board depicts a rounded app tile and a perspective installer box.
# Clip each illustration to its outline, excluding its caption and backdrop.
$tile = Crop 1077 59 377 341
$box = Crop 1123 485 280 299
function Clip-Art($source, $path) {
    $target = Canvas $source.Width $source.Height
    $g = [Drawing.Graphics]::FromImage($target)
    $brush = [Drawing.TextureBrush]::new($source)
    try {
        $g.SmoothingMode = 'AntiAlias'
        $g.FillPath($brush,$path)
    } finally { $brush.Dispose(); $g.Dispose(); $path.Dispose() }
    $target
}
$outline = [Drawing.Drawing2D.GraphicsPath]::new()
foreach ($arc in @(@(1,1,180),@(238,1,270),@(238,202,0),@(1,202,90))) {
    $outline.AddArc($arc[0],$arc[1],137,137,$arc[2],90)
}
$outline.CloseFigure()
$appTile = Clip-Art $tile $outline
$outline = [Drawing.Drawing2D.GraphicsPath]::new()
$points = [Drawing.Point[]]@(foreach ($xy in @(@(2,36),@(8,27),@(45,7),@(59,2),@(259,17),@(275,23),@(279,37),@(279,265),@(277,278),@(48,297),@(37,296),@(4,283),@(1,278))) {
    [Drawing.Point]::new($xy[0],$xy[1])
})
$outline.AddPolygon($points)
$installerBox = Clip-Art $box $outline

function Export-Icon($prefix, $large, $filename) {
    $sizes = @(16,24,32,48,64,128,256)
    $entries = foreach ($size in $sizes) {
        # Both small icons favor the silver profile over a scaled frame or tiny lettering.
        $source = if ($size -le 32) { $crest } else { $large }
        $scale = $size / [Math]::Max($source.Width,$source.Height)
        $w = [int][Math]::Round($source.Width * $scale)
        $h = [int][Math]::Round($source.Height * $scale)
        $canvas = Canvas $size $size
        Paint $canvas $source ([int](($size-$w)/2)) ([int](($size-$h)/2)) $w $h
        $png = Join-Path $icons "$prefix-$size.png"
        Save-Png $canvas $png
        $canvas.Dispose()
        [pscustomobject]@{ Size=$size; Bytes=[IO.File]::ReadAllBytes($png) }
    }
    $writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $windows $filename)))
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$entries.Count)
        $offset = 6 + 16 * $entries.Count
        foreach ($entry in $entries) {
            $dim = [byte]($entry.Size % 256)
            $writer.Write($dim); $writer.Write($dim)
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$entry.Bytes.Length); $writer.Write([uint32]$offset)
            $offset += $entry.Bytes.Length
        }
        foreach ($entry in $entries) { $writer.Write([byte[]]$entry.Bytes) }
    } finally { $writer.Dispose() }
}
Export-Icon 'app' $appTile 'app_icon.ico'
Export-Icon 'setup' $installerBox 'setup_icon.ico'
foreach ($bitmap in @($board,$original,$crest,$word,$horizontal,$compact,$emblem,$tile,$box,$appTile,$installerBox)) { $bitmap.Dispose() }
