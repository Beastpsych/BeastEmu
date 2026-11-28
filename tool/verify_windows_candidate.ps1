#requires -Version 7.0
param([Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$manifest = @(Get-Content -LiteralPath (Join-Path $root 'portable.json') -Raw | ConvertFrom-Json)
$zip = @(Get-ChildItem -LiteralPath $root -File -Filter '*.zip')
$exe = @(Get-ChildItem -LiteralPath $root -File -Filter '*Setup.exe')
if ($zip.Count -ne 1 -or $exe.Count -ne 1) { throw 'Esperado um ZIP e um instalador.' }
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([A-Fa-f0-9]{64})  (.+)$') { throw 'Manifesto SHA-256 inválido.' }
    $expected = $Matches[1]
    $name = $Matches[2]
    if ([IO.Path]::GetFileName($name) -cne $name) { throw 'Nome de artefato inválido.' }
    if ((Get-FileHash -LiteralPath (Join-Path $root $name)).Hash -cne $expected) { throw "SHA-256 divergente: $name" }
}
$archive = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
try {
    if ($archive.Entries.Count -ne $manifest.Count) { throw 'Contagem do ZIP diverge do manifesto.' }
    foreach ($item in $manifest) {
        $entry = $archive.GetEntry($item.path.Replace('\','/'))
        if (!$entry -or $entry.Length -ne $item.bytes) { throw "Entrada ausente ou truncada: $($item.path)" }
        $stream = $entry.Open()
        try { $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) }
        finally { $stream.Dispose() }
        if ($digest -cne $item.sha256) { throw "Conteúdo divergente: $($item.path)" }
    }
} finally { $archive.Dispose() }
$payload = @(Get-Content -LiteralPath (Join-Path $root 'payload.json') -Raw | ConvertFrom-Json)
foreach ($required in @('helpers\sameboy-live.exe','helpers\mgba-live.exe','cores\windows\sameboy_libretro.dll','cores\windows\mgba_libretro.dll','LICENSE','MARCA.md','licenses\mGBA-FONTES.md')) {
    if ($required -notin $payload.path) { throw "Instalador sem $required" }
}
if ($exe[0].VersionInfo.ProductVersion.Trim() -cne '0.2.0-beta.1+4') { throw 'Versão inesperada do candidato.' }
Write-Output "Integridade confirmada: $($manifest.Count) arquivos no ZIP e $($payload.Count) no manifesto do instalador."
Write-Output "Assinatura do instalador: $((Get-AuthenticodeSignature -LiteralPath $exe[0].FullName).Status)"
Write-Output 'Instalação, atualização e desinstalação permanecem sujeitas a teste em conta descartável.'
