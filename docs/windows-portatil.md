# BeastEmu 0.2.0-beta.1 · build 4 para Windows x64

O pacote atual inclui SameBoy para GB/GBC e mGBA para GBA. Ambos usam o perfil público BeastEmu. Os dados GBA ficam em `%LOCALAPPDATA%\BeastEmu\saves\mgba` e `states\mgba`, por SHA-256 da ROM. Siga `BETA-0.2.md` para atualização e importação opcional do GBA Dev. Consulte `licenses/mGBA-FONTES.md` para obter os fontes da revisão mGBA. A instalação GBA Dev permanece separada.

## Orientações e registro da beta 0.1.1

Abra `beastemu.exe` dentro da pasta completa. O Windows precisa do runtime Microsoft Visual C++ v14 x64 e do XAudio2 do sistema. Os auxiliares em `helpers` incluem o runtime Dart. Para iniciar uma sessão, selecione **Jogar** no card da biblioteca.

A biblioteca abre os jogos que você importar. Saves de cartucho e slots ficam em `%LOCALAPPDATA%\BeastEmu\saves` e `%LOCALAPPDATA%\BeastEmu\states`. A biblioteca, as capas e as preferências continuam na pasta de suporte da conta Windows. Mover a pasta de executáveis preserva esses dados na conta de origem.

Na janela do jogo, **Salvar estado** e **Carregar estado** abrem os cinco slots da ROM. Após carregar um slot, use os slots para guardar o progresso dessa sessão. Reabra o jogo para voltar à gravação normal do cartucho.

F5 grava o slot rápido exclusivo do jogo e F9 o carrega. Os cinco slots manuais continuam separados. **Acelerar** ou F8 percorre 1×, 2×, 3× e 4×. Tab aplica 4× enquanto pressionada. Soltar a tecla ou mudar de janela recupera a velocidade selecionada. O áudio retorna em 1× com o volume e o mudo escolhidos. M alterna o mudo e F11 alterna a tela cheia. Ajuste as seis teclas em **Configurações → Atalhos do emulador**. Um mapeamento antigo em conflito tem prioridade e o painel permite escolher uma tecla livre.

Em **Configurações → Controles Xbox / XInput**, pressione os botões para conferir a leitura e use o lápis ao lado de cada ação para remapear. O direcional e o analógico esquerdo compartilham as quatro direções. O mapeamento é salvo para a conta Windows e vale para os controles XInput. O primeiro controle conectado na ordem mostrada opera o jogo junto com o teclado. Ao voltar de outro aplicativo ou reconectar o controle, solte os botões e centralize o analógico.

## Conferir o Link Cable Local

Em **Biblioteca → Link Cable Local**, selecione um cartucho GB/GBC por jogador e clique em **Conectar**. O jogador 1 fica à esquerda e usa o teclado. Com um controle XInput conectado, ele controla o jogador 2. Com dois, o primeiro controla J1 e o segundo controla J2. O áudio vem da tela esquerda.

O modo experimental inicia uma coleção separada de saves, por ROM e por posição de jogador. Mantenha a mesma posição para retomar o progresso. Use **Sair** para concluir as duas gravações.

Para testar com os cartuchos de demonstração, execute `dart run tool/link_demo_roms.dart` na raiz do projeto. Importe os dois arquivos da pasta indicada, selecione **LINK LEFT** para J1 e **LINK RIGHT** para J2 e espere as duas telas clarearem. Pressione **B no jogador 2** até a direita ficar cinza-claro. Depois pressione **A no jogador 1**. A esquerda escurece e a direita passa a cinza-escuro após a troca. A demonstração faz uma transferência por abertura.

## Gerar o portátil

Na raiz do checkout, execute `flutter build windows` e depois `dart run tool/package_windows.dart`. Cada execução bem-sucedida gera uma pasta nova em `build/portable`. O script usa a DLL local validada e copia somente os componentes de execução, as instruções e os avisos de licença.

## Componentes e validação

A DLL local anuncia SameBoy 1.0.5, revisão `90e2899`. O hash SHA-256 usado nesta versão é `491aaf9074ef2f1cf641d87b3b17f44d488e648d111cd48825072d95916d7d7b`. A pasta `licenses` contém a licença Expat do núcleo e os avisos dos runtimes Dart e Flutter. Os avisos dos pacotes Flutter estão em `data/flutter_assets/NOTICES.Z`. [Revisão do núcleo](https://github.com/libretro/SameBoy/commit/90e2899) · [Licença do núcleo](https://raw.githubusercontent.com/LIJI32/SameBoy/90e2899/LICENSE)

A raiz do portátil inclui a licença MIT do código autoral em `LICENSE` e a política dos recursos visuais em `MARCA.md`. Compare o SHA-256 do ZIP com o valor fornecido para esta compilação. O proprietário relatou testes manuais do candidato anterior em dois computadores Windows. [Distribuição para Windows com Flutter](https://docs.flutter.dev/platform-integration/windows/building) · [Runtime Microsoft Visual C++](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)
