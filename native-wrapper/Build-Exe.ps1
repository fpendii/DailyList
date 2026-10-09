param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Daftar Harian.exe')
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$iconPath = Join-Path $projectRoot 'assets\app-icon.ico'
$automationAssembly = 'C:\Windows\Microsoft.Net\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
if (-not (Test-Path -LiteralPath $compiler)) { throw "C# compiler tidak ditemukan: $compiler" }
if (-not (Test-Path -LiteralPath $iconPath)) { throw "Ikon aplikasi tidak ditemukan: $iconPath" }
if (-not (Test-Path -LiteralPath $automationAssembly)) { throw 'PowerShell automation assembly tidak ditemukan.' }

$resourceMap = [ordered]@{
    'DaftarHarian.Script'                 = 'DailyListPopup.ps1'
    'DaftarHarian.Icon'                   = 'assets\app-icon.ico'
    'DaftarHarian.Assets.Cat1.OpenEyes'   = 'assets\cat-expressions-1\buka mata.png'
    'DaftarHarian.Assets.Cat1.Angry'      = 'assets\cat-expressions-1\marah.png'
    'DaftarHarian.Assets.Cat1.Blink'      = 'assets\cat-expressions-1\merem.png'
    'DaftarHarian.Assets.Cat1.Yawn'       = 'assets\cat-expressions-1\nguap.png'
    'DaftarHarian.Assets.Cat1.Sleep'      = 'assets\cat-expressions-1\tidur.png'
    'DaftarHarian.Assets.Cat2.Confused'   = 'assets\cat-expressions-2\Bingung.png'
    'DaftarHarian.Assets.Cat2.Love'       = 'assets\cat-expressions-2\Cinta.png'
    'DaftarHarian.Assets.Cat2.Nervous'    = 'assets\cat-expressions-2\Grogi.png'
    'DaftarHarian.Assets.Cat2.Tired'      = 'assets\cat-expressions-2\lelah.png'
    'DaftarHarian.Assets.Cat2.Shy'        = 'assets\cat-expressions-2\Malu.png'
    'DaftarHarian.Assets.Cat2.Panic'      = 'assets\cat-expressions-2\Panik.png'
    'DaftarHarian.Assets.Cat2.Curious'    = 'assets\cat-expressions-2\Penasaran.png'
    'DaftarHarian.Assets.Cat2.Sad'        = 'assets\cat-expressions-2\Sedih.png'
    'DaftarHarian.Assets.Cat2.Happy'      = 'assets\cat-expressions-2\Senang.png'
    'DaftarHarian.Assets.Cat2.Surprised'  = 'assets\cat-expressions-2\Terkejut.png'
}

$arguments = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', "/win32icon:$iconPath",
    "/out:$OutputPath",
    "/reference:$automationAssembly",
    '/reference:System.Windows.Forms.dll',
    (Join-Path $PSScriptRoot 'Program.cs')
)

foreach ($resource in $resourceMap.GetEnumerator()) {
    $arguments += "/resource:$((Join-Path $projectRoot $resource.Value)),$($resource.Key)"
}

& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'Kompilasi EXE gagal.' }
