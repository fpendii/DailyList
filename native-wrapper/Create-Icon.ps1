param(
    [string]$IconPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\app-icon.ico'),
    [string]$PreviewPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\app-icon.png')
)

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@

function New-RoundedPath([float]$x, [float]$y, [float]$width, [float]$height, [float]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $width - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $width - $d, $y + $height - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $height - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

New-Item -ItemType Directory -Path (Split-Path -Parent $IconPath) -Force | Out-Null
$bitmap = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

try {
    # Violet rounded app tile.
    $tile = New-RoundedPath 10 10 236 236 58
    $tileBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#4F46E5'))
    $graphics.FillPath($tileBrush, $tile)
    $tileBrush.Dispose(); $tile.Dispose()

    # Checklist card.
    $shadow = New-RoundedPath 34 40 143 174 27
    $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, 15, 23, 42))
    $graphics.FillPath($shadowBrush, $shadow)
    $shadowBrush.Dispose(); $shadow.Dispose()
    $card = New-RoundedPath 28 33 143 174 27
    $cardBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#F8FAFC'))
    $graphics.FillPath($cardBrush, $card)
    $cardBrush.Dispose(); $card.Dispose()

    # Three task rows.
    $check = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#10B981'), 9)
    $check.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $check.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $line = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#94A3B8'), 9)
    $line.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $line.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLines($check, [System.Drawing.Point[]]@((New-Object System.Drawing.Point 48,82), (New-Object System.Drawing.Point 57,91), (New-Object System.Drawing.Point 73,70)))
    $graphics.DrawLine($line, 91, 81, 145, 81)
    $graphics.DrawLines($check, [System.Drawing.Point[]]@((New-Object System.Drawing.Point 48,123), (New-Object System.Drawing.Point 57,132), (New-Object System.Drawing.Point 73,111)))
    $graphics.DrawLine($line, 91, 122, 145, 122)
    $graphics.DrawEllipse($line, 48, 151, 24, 24)
    $graphics.DrawLine($line, 91, 163, 134, 163)
    $check.Dispose(); $line.Dispose()

    # Orange cat face.
    $outline = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#9A3412'), 6)
    $ears = New-Object System.Drawing.Drawing2D.GraphicsPath
    $ears.AddPolygon([System.Drawing.Point[]]@((New-Object System.Drawing.Point 157,182), (New-Object System.Drawing.Point 165,139), (New-Object System.Drawing.Point 185,157)))
    $ears.AddPolygon([System.Drawing.Point[]]@((New-Object System.Drawing.Point 211,157), (New-Object System.Drawing.Point 231,139), (New-Object System.Drawing.Point 239,182)))
    $catColor = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#FDBA74'))
    $graphics.FillPath($catColor, $ears); $graphics.DrawPath($outline, $ears)
    $graphics.FillEllipse($catColor, 157, 151, 82, 78); $graphics.DrawEllipse($outline, 157, 151, 82, 78)
    $ears.Dispose(); $catColor.Dispose()
    $face = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#1E293B'))
    $graphics.FillEllipse($face, 179, 179, 8, 11); $graphics.FillEllipse($face, 211, 179, 8, 11)
    $face.Dispose()
    $nose = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#F43F5E'))
    $graphics.FillEllipse($nose, 196, 193, 9, 7); $nose.Dispose()
    $smile = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#9A3412'), 4)
    $smile.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $smile.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($smile, 185, 193, 16, 15, 5, 72); $graphics.DrawArc($smile, 200, 193, 16, 15, 103, 72)
    $smile.Dispose(); $outline.Dispose()

    $bitmap.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $handle = $bitmap.GetHicon()
    try {
        $temporary = [System.Drawing.Icon]::FromHandle($handle)
        $icon = [System.Drawing.Icon]$temporary.Clone()
        try {
            $stream = New-Object System.IO.FileStream($IconPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try { $icon.Save($stream) } finally { $stream.Dispose() }
        } finally { $icon.Dispose() }
    } finally {
        [void][NativeIcon]::DestroyIcon($handle)
    }
} finally {
    $graphics.Dispose(); $bitmap.Dispose()
}
