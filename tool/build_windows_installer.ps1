#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableDirectory,
    [string]$Compiler = 'ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bundle = (Resolve-Path -LiteralPath $PortableDirectory).Path
$iscc = (Get-Command $Compiler -CommandType Application -ErrorAction Stop).Source
$compilerDir = Split-Path -Parent $iscc

function Read-Setting([string]$Path, [string]$Pattern) {
    $match = [regex]::Match((Get-Content -LiteralPath (Join-Path $repo $Path) -Raw), $Pattern)
    if (!$match.Success) { throw "Configuração ausente em $Path" }
    $match.Groups[1].Value
}
$app = Read-Setting 'lib/main.dart' "(?m)^\s*title:\s*'([A-Za-z0-9 _-]+)',"
$exe = (Read-Setting 'windows/CMakeLists.txt' 'set\(BINARY_NAME "([A-Za-z0-9_-]+)"\)') + '.exe'
$version = Read-Setting 'pubspec.yaml' '(?m)^version:\s*([A-Za-z0-9.+-]+)\s*$'
$vi = (Get-Item -LiteralPath (Join-Path $bundle $exe)).VersionInfo
if ($vi.ProductVersion -cne $version) { throw "Release $($vi.ProductVersion) difere do pubspec $version." }
if ($vi.CompanyName -cne 'BeastEmu' -or $vi.ProductName -cne $app -or $vi.FileDescription -cne $app) {
    throw 'A identidade do executável diverge do perfil de dados desta versão.'
}
$numeric = "$($vi.ProductMajorPart).$($vi.ProductMinorPart).$($vi.ProductBuildPart).$($vi.ProductPrivatePart)"
$vc = [version](Read-Setting 'build/windows/x64/CMakeCache.txt' '(?im)^CMAKE_LINKER:FILEPATH=.*[/\\]MSVC[/\\](14\.\d+\.\d+)[/\\]')

# Only these portable files are eligible. Review new assets or dependencies explicitly.
$runtime = @(
    $exe, 'beastemu_audio.dll', 'flutter_windows.dll', 'dartjni.dll',
    'helpers\sameboy-live.exe', 'helpers\sameboy-preview.exe', 'cores\windows\sameboy_libretro.dll',
    'data\app.so', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin',
    'data\flutter_assets\FontManifest.json', 'data\flutter_assets\NativeAssetsManifest.json',
    'data\flutter_assets\NOTICES.Z', 'data\flutter_assets\fonts\MaterialIcons-Regular.otf',
    'data\flutter_assets\packages\cupertino_icons\assets\CupertinoIcons.ttf',
    'data\flutter_assets\assets\brand\logo-horizontal.png', 'data\flutter_assets\assets\brand\logo-compact.png',
    'data\flutter_assets\assets\brand\emblem.png', 'data\flutter_assets\assets\brand\symbol.png',
    'data\flutter_assets\shaders\ink_sparkle.frag', 'data\flutter_assets\shaders\stretch_effect.frag',
    'LICENSE', 'LEIA-ME.md', 'licenses\Dart.txt', 'licenses\Flutter.txt', 'licenses\Flutter-Engine.txt',
    'licenses\Flutter-Windows.md', 'licenses\SameBoy.txt', 'licenses\Libretro.txt',
    'licenses\CREDITOS.md', 'licenses\MaterialIcons.txt', 'licenses\CupertinoIcons.txt',
    'licenses\Flutter-template-images.txt'
)
$available = @(Get-ChildItem -LiteralPath $bundle -Recurse -Force -File | ForEach-Object {
    [IO.Path]::GetRelativePath($bundle, $_.FullName)
})
$difference = Compare-Object $runtime $available
if ($difference) { throw "Conteúdo inesperado ou ausente no portátil: $($difference.InputObject -join ', ')" }
if ((Get-FileHash -LiteralPath (Join-Path $bundle 'LICENSE')).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $repo 'LICENSE')).Hash) {
    throw 'A licença do portátil diverge da licença do repositório.'
}
$files = [ordered]@{}
foreach ($path in $runtime) { $files[$path] = Join-Path $bundle $path }
$files['icons\beastemu-dragon.ico'] = Join-Path $repo 'windows/runner/resources/app_icon.ico'
$files['INSTALACAO.md'] = Join-Path $repo 'docs/windows-instalador.md'
$files['licenses\InnoSetup.txt'] = Join-Path $compilerDir 'license.txt'

$output = Join-Path $repo ("build/installer/" + $version + "/" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $output
$list = Join-Path $output 'payload.iss'
$manifest = foreach ($dest in $files.Keys) {
    $source = Get-Item -LiteralPath $files[$dest]
    $dir = Split-Path -Parent $dest
    $target = if ($dir) { "{app}\$dir" } else { '{app}' }
    $leaf = Split-Path -Leaf $dest
    Add-Content -LiteralPath $list -Encoding utf8BOM -Value (
        'Source: "{0}"; DestDir: "{1}"; DestName: "{2}"; Flags: ignoreversion' -f $source.FullName, $target, $leaf)
    [ordered]@{ path = $dest; bytes = $source.Length; sha256 = (Get-FileHash -LiteralPath $source.FullName).Hash }
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'payload.json') -Encoding utf8
$options = @('/Qp', "/DPayloadList=$list", "/DArtifacts=$output", "/DAppTitle=$app", "/DAppExe=$exe",
    "/DAppVersionText=$version", "/DNumericVersion=$numeric", "/DVcMajor=$($vc.Major)",
    "/DVcMinor=$($vc.Minor)", "/DVcBuild=$($vc.Build)", (Join-Path $repo 'windows/installer/beastemu.iss'))
& $iscc @options
if ($LASTEXITCODE) { throw "Falha do Inno Setup ($LASTEXITCODE)." }
$setup = Get-Item -LiteralPath (Join-Path $output "$app-$version-Windows-x64-Setup.exe")
if ($setup.VersionInfo.ProductVersion.Trim() -cne $version -or
    ($setup.VersionInfo.ProductVersionRaw.ToString()) -ne $numeric) {
    throw 'O recurso de versão do instalador diverge do executável.'
}
$hash = (Get-FileHash -LiteralPath $setup.FullName).Hash
"$hash  $($setup.Name)" | Set-Content -LiteralPath "$($setup.FullName).sha256" -Encoding ascii
Write-Output "$($setup.FullName) ($($setup.Length) bytes)"
Write-Output "SHA-256 $hash"

$zipName = "$app-$version-Windows-x64-Portable.zip"
$zipPath = Join-Path $output $zipName
[IO.Compression.ZipFile]::CreateFromDirectory($bundle, $zipPath)
$zipHash = (Get-FileHash -LiteralPath $zipPath).Hash
@("$hash  $($setup.Name)", "$zipHash  $zipName") |
    Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
$manifest | Where-Object { $_.path -in $runtime } | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $output 'portable.json') -Encoding utf8
Write-Output "$zipPath ($((Get-Item -LiteralPath $zipPath).Length) bytes)"
Write-Output "SHA-256 $zipHash"
