# BeastEmu 0.1.1-beta.1 · build 3 para Windows x64

Esta beta local inclui emulação de Game Boy e Game Boy Color. O modo de um jogador é o padrão. **Link Cable Local** é experimental e usa saves separados para cada jogador.

## Instalar e abrir

1. Use Windows 10 ou 11 x64 em um processador Intel ou AMD. O áudio e os controles Xbox usam o XAudio2 e o XInput do Windows. A lista de plataformas do Flutter inclui Windows 10 e 11. [Plataformas do Flutter](https://docs.flutter.dev/reference/supported-platforms)
2. Instale o Microsoft Visual C++ v14 Redistributable **x64** se solicitado. A compilação com o toolset 14.51.36231 requer essa versão ou uma mais recente. O assistente verifica o registro do runtime e informa a versão exigida pelo build. O pacote da Microsoft pode pedir permissão de administrador. [Download oficial da Microsoft](https://learn.microsoft.com/pt-br/cpp/windows/latest-supported-vc-redist)
3. Execute o arquivo `BeastEmu-<versão>-Windows-x64-Setup.exe`. O assistente em português instala o programa na sua conta, em `%LOCALAPPDATA%\Programs\BeastEmu`. O atalho da área de trabalho é opcional. Abra **BeastEmu** pelo menu Iniciar ou pela última página do assistente.
4. Em **Biblioteca → Adicionar jogos GB/GBC**, escolha arquivos próprios `.gb` ou `.gbc` extraídos e selecione **Jogar**. O pacote inclui os auxiliares compilados, o núcleo e os recursos gráficos. Flutter, Dart, Java e editores de código são dispensáveis para jogar.

## Atualizar e desinstalar

Encerre o jogo por **Sair**, aguarde a gravação e feche o aplicativo. Execute o instalador da próxima versão na mesma conta. Ele usa o mesmo identificador e diretório. A versão instalada e a portátil compartilham os dados da conta. Use uma sessão por vez para o mesmo save.

Para remover o programa, abra **Configurações → Aplicativos → Aplicativos instalados** (ou **Aplicativos e recursos** no Windows 10), localize **BeastEmu** e escolha **Desinstalar**. Os dados abaixo continuam disponíveis para uma reinstalação.

| Dados | Local |
|---|---|
| Saves de cartucho e RTC | `%LOCALAPPDATA%\BeastEmu\saves` |
| Saves do Link Cable | `%LOCALAPPDATA%\BeastEmu\saves\link\p1` e `p2` |
| Save states | `%LOCALAPPDATA%\BeastEmu\states` |
| Perfil de instalações novas, incluindo índice da biblioteca e gamepad em `shared_preferences.json` | `%APPDATA%\BeastEmu\BeastEmu` |
| ROMs importadas, capas, volume e teclado de instalações anteriores | `%APPDATA%\com.example\beastemu`, incluindo `beastemu_roms` e `covers` |

A partir de `0.1.0-beta.rc.2+2`, empresa e produto no executável são BeastEmu. No primeiro uso após atualizar, a aplicação copia o índice da biblioteca, favoritos, recentes e controles do JSON antigo para o novo perfil. A cópia é validada e gravada antes da abertura da biblioteca. Um destino existente tem prioridade. ROMs, capas, opções de emulação e teclado de quem atualizou continuam no diretório anterior, mantendo válidos os caminhos absolutos. Conserve as duas pastas ao fazer backup. Use a mesma versão para acessar o catálogo após atualizar.

## Conferir ou renovar o ícone de um atalho

1. Feche o BeastEmu e execute o instalador atualizado na mesma conta. Marque **Criar atalho na Área de Trabalho** se quiser esse segundo atalho. O menu Iniciar recebe seu atalho em toda instalação.
2. Pressione **Win + R**, digite `shell:programs` e abra as **Propriedades** do atalho BeastEmu. Na aba **Atalho**, o destino deve ser `%LOCALAPPDATA%\Programs\BeastEmu\beastemu.exe`. Em **Alterar ícone**, confira o arquivo `%LOCALAPPDATA%\Programs\BeastEmu\icons\beastemu-dragon.ico`. O Windows pode mostrar esses caminhos por extenso. Repita a conferência em `shell:desktop` para o atalho opcional.
3. Se um atalho criado manualmente ainda usar a imagem antiga, escolha esse ICO em **Alterar ícone**, confirme em **OK → Aplicar** e pressione **F5**. Para renovar um item fixado, desafixe o antigo e fixe o BeastEmu a partir da entrada atualizada do menu Iniciar. [Personalizar a barra de tarefas do Windows](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-taskbar-in-windows)
4. Se os caminhos já estiverem corretos e a imagem continuar antiga, aguarde o fim de cópias de arquivos, abra o **Gerenciador de Tarefas** e selecione **Windows Explorer → Reiniciar**. Outra opção é sair da conta e entrar novamente. Isso solicita uma nova exibição dos atalhos sem apagar dados do aplicativo.

O executável e a janela usam o ícone do aplicativo incorporado ao programa. O instalador tem sua própria imagem de caixa. Os atalhos instalados apontam explicitamente para o ICO do aplicativo, índice zero, em uma pasta permanente da instalação.

## Conteúdo e licenças

O diretório `licenses` contém a licença Expat do SameBoy, os avisos BSD de Flutter e Dart, os avisos do engine Windows e o texto de licença das fontes Material Icons. O Flutter gera `data\flutter_assets\NOTICES.Z` com os créditos dos pacotes e recursos de terceiros, incluindo Cupertino Icons. O instalador usa Inno Setup e inclui seu aviso de licença. O arquivo `LICENSE` na pasta de instalação contém a licença MIT do código autoral do BeastEmu. Ao seu lado, `MARCA.md` descreve as permissões de uso do nome, do emblema, do logotipo e dos ícones.

O instalador é distribuído sem assinatura Authenticode. O SmartScreen pode exibir um aviso de aplicativo desconhecido. Confira a origem e o SHA-256 antes de executá-lo. O hash permite comparar o arquivo com a cópia indicada pelo mantenedor.

## Reproduzir o instalador

Na máquina de desenvolvimento, use o SDK Flutter do projeto, o toolset C++ para Windows, PowerShell 7 e o compilador oficial Inno Setup 7 x64. [Inno Setup](https://jrsoftware.org/inno-setup/downloads)

```powershell
flutter analyze
flutter build windows
dart run tool/package_windows.dart
# Use a pasta impressa pelo empacotador.
$portable = Read-Host 'Pasta do portátil'
$env:BEASTEMU_TEST_PACKAGE = (Resolve-Path -LiteralPath $portable).Path
flutter test --concurrency=1
./tool/build_windows_installer.ps1 -PortableDirectory $portable -Compiler (Read-Host 'Caminho do ISCC.exe')
```

O script confere o nome e a versão, compara o conteúdo do portátil com a lista de arquivos permitidos e obtém a versão do toolset no cache CMake da compilação. Cada execução cria uma pasta nova em `build\installer\<versão>`, com o instalador, o SHA-256 e o inventário `payload.json` para conferir os arquivos instalados. O argumento `-Compiler` também aceita o caminho do ISCC extraído da distribuição oficial. A versão numérica do recurso Windows e a versão beta exibida são lidas separadamente.

## Validar em outra máquina

Em uma conta descartável ou VM Windows x64, confira o hash e instale a versão anterior. Importe uma ROM sintética, ajuste o volume e feche. Instale a beta sobre o RC2. Verifique uma única entrada em Aplicativos instalados, os atalhos, a versão e a abertura pelo menu Iniciar. Confirme que a biblioteca, a capa, o progresso e o volume reaparecem. Desinstale, confira os diretórios de dados da tabela e reinstale para retomar o progresso.

Para verificar automaticamente o ciclo de instalação na conta de teste, copie os dois instaladores, o `payload.json` do candidato e `tool/test_windows_installer.ps1`. Execute o script com `-Installer <exe-da-beta> -PreviousInstaller <exe-do-RC2> -DisposableProfile`. Em outra conta descartável, omita o instalador anterior para testar a instalação direta. O teste verifica registro, atalhos, abertura, migração do catálogo sintético, reinstalação, integridade e preservação dos dados de teste após desinstalar.

O diretório do instalador também contém o ZIP portátil, os inventários `portable.json` e `payload.json` (nome, tamanho e SHA-256 de cada arquivo), além de `SHA256SUMS.txt` para verificar os dois downloads. Em PowerShell, use `Get-FileHash -Algorithm SHA256 -LiteralPath <arquivo>` e compare o valor completo.
