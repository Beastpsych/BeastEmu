#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer, [string]$PreviousInstaller, [switch]$DisposableProfile)
$ErrorActionPreference = 'Stop'
if (!$DisposableProfile -or ![Environment]::Is64BitProcess) {
    throw 'Execute em PowerShell x64 dentro de uma conta descartável e informe -DisposableProfile.'
}
$setup = Get-Item -LiteralPath $Installer
$manifest = @(Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $setup.DirectoryName 'payload.json') | ConvertFrom-Json)
$local = [Environment]::GetFolderPath('LocalApplicationData')
$app = Join-Path $local 'Programs\BeastEmu'
$data = Join-Path $local 'BeastEmu'
$roaming = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'com.example\beastemu'
$currentProfile = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'BeastEmu\BeastEmu'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'BeastEmu.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'BeastEmu.lnk'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{EA0278D8-06C3-4CE8-9AC3-0219910142EE}_is1'
foreach ($path in @($app,$data,$roaming,$currentProfile,$menu,$desktop,$key)) {
    if (Test-Path -LiteralPath $path) { throw "Perfil já contém $path. Use uma conta de teste nova." }
}
$qa = Join-Path ([IO.Path]::GetTempPath()) ('BeastEmu Installer QA ' + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $qa
$exe = Join-Path $app 'beastemu.exe'
$shell = New-Object -ComObject WScript.Shell
function Run-Setup([string]$Program, [string[]]$Options) {
    $job = Start-Process -FilePath $Program -ArgumentList $Options -WorkingDirectory $qa -WindowStyle Hidden -PassThru -Wait
    if ($job.ExitCode -ne 0) { throw "$Program encerrou com código $($job.ExitCode)." }
}
function Assert-Shortcut([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { throw "Atalho ausente: $Path" }
    $link = $shell.CreateShortcut($Path)
    $icon = Join-Path $app 'icons\beastemu-dragon.ico'
    if ($link.TargetPath -ne $exe -or $link.WorkingDirectory -ne $app -or
        $link.IconLocation -ne "$icon,0") {
        throw "Destino, pasta ou ícone incorreto em $Path."
    }
}
function Assert-Installed {
    $record = Get-ItemProperty -LiteralPath $key
    if ($record.DisplayName -notlike 'BeastEmu*' -or $record.DisplayVersion -cne $setup.VersionInfo.ProductVersion.Trim() -or
        $record.InstallLocation.TrimEnd('\') -ne $app) { throw 'Registro de instalação incorreto.' }
    foreach ($entry in $manifest) {
        $file = Get-Item -LiteralPath (Join-Path $app $entry.path)
        if ($file.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne $entry.sha256) {
            throw "Conteúdo instalado divergente: $($entry.path)"
        }
    }
    Assert-Shortcut $menu
}
$markers = @(
    (Join-Path $data 'saves\qa.cart'), (Join-Path $data 'saves\link\p1\qa.cart'),
    (Join-Path $data 'saves\link\p2\qa.cart'), (Join-Path $data 'states\qa\qa.state'),
    (Join-Path $roaming 'covers\qa.png'), (Join-Path $roaming 'beastemu_roms\qa.gb'),
    (Join-Path $roaming 'keyboard-bindings-v1.json'), (Join-Path $roaming 'emulation-settings-v1.json'),
    (Join-Path $roaming 'shared_preferences.json')
)
$sentinelHashes = @{}
foreach ($marker in $markers) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $marker))
    [IO.File]::WriteAllText($marker, '{}')
    $sentinelHashes[$marker] = (Get-FileHash -LiteralPath $marker).Hash
}
function Assert-UserData {
    foreach ($marker in $markers) {
        if ((Get-FileHash -LiteralPath $marker).Hash -ne $sentinelHashes[$marker]) {
            throw "Dado de teste modificado: $marker"
        }
    }
}
$quiet = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-')
if ($PreviousInstaller) {
    $previous = Get-Item -LiteralPath $PreviousInstaller
    if ((Get-FileHash -LiteralPath $previous.FullName).Hash -eq (Get-FileHash -LiteralPath $setup.FullName).Hash) {
        throw 'Use um instalador anterior diferente do candidato.'
    }
    Run-Setup $previous.FullName $quiet
    if ((Get-ItemProperty -LiteralPath $key).DisplayVersion -cne $previous.VersionInfo.ProductVersion.Trim()) {
        throw 'A versão anterior não registrou o AppId esperado.'
    }
}
Run-Setup $setup.FullName $quiet
Assert-Installed
Assert-UserData
if (Test-Path -LiteralPath $desktop) { throw 'Atalho de desktop criado sem seleção.' }

# Verify a real Flutter window without a development toolchain on PATH.
$pathBefore = $env:Path
try {
    $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
    $game = Start-Process -FilePath $exe -WorkingDirectory $qa -PassThru -WindowStyle Normal
    $limit = [DateTime]::UtcNow.AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 250
        $game.Refresh()
    } until ($game.HasExited -or $game.MainWindowHandle -ne 0 -or [DateTime]::UtcNow -gt $limit)
    if ($game.HasExited -or !$game.MainWindowHandle -or !$game.Responding) { throw 'Janela Flutter indisponível.' }
    if (!$game.CloseMainWindow() -or !$game.WaitForExit(15000)) { throw 'Feche a sessão de teste antes de continuar.' }
} finally { $env:Path = $pathBefore }

$migrated = Join-Path $currentProfile 'shared_preferences.json'
if ((Get-FileHash -LiteralPath $migrated).Hash -ne $sentinelHashes[(Join-Path $roaming 'shared_preferences.json')]) {
    throw 'O catálogo anterior não foi preservado no novo perfil.'
}
$markers += $migrated
$sentinelHashes[$migrated] = (Get-FileHash -LiteralPath $migrated).Hash
Run-Setup $setup.FullName ($quiet + '/TASKS=desktopicon')
Assert-Installed
Assert-UserData
Assert-Shortcut $desktop
$uninstall = (Get-ItemProperty -LiteralPath $key).UninstallString.Trim('"')
if ($uninstall -ne (Join-Path $app 'unins000.exe')) { throw 'Desinstalador inesperado. Teste interrompido.' }
Run-Setup $uninstall $quiet
foreach ($path in @($exe,$key,$menu,$desktop)) {
    if (Test-Path -LiteralPath $path) { throw "Item instalado remanescente: $path" }
}
foreach ($entry in $manifest) {
    if (Test-Path -LiteralPath (Join-Path $app $entry.path)) { throw "Arquivo instalado remanescente: $($entry.path)" }
}
Assert-UserData
Write-Output 'Smoke test de instalação, atalhos, abertura, reinstalação e desinstalação concluído com marcadores. A leitura de progresso real e o ciclo definitivo exigem docs/validacao-final-0.2.md.'
