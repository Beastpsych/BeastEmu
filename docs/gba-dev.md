# Game Boy Advance experimental · Windows x64

Este build local usa um perfil de desenvolvimento. Importe somente cartuchos sintéticos ou homebrew de teste. Para guardar o progresso, use o menu interno de um jogo com memória de cartucho e aguarde o fechamento da sessão. A sessão individual mantém o teclado configurado e aceita direcional, A, B, Start e Select. Q e E acionam L e R quando livres de outros mapeamentos. No controle XInput, use LB e RB. A janela preserva a proporção, permite ajustar volume ou mudo e encerra o auxiliar ao sair.

## Testar o marco

1. Na raiz da cópia de desenvolvimento, execute `dart run tool/gba_demo.dart build/Beast-Input.gba`. O gerador cria um arquivo novo e recusa sobrescrever um existente.
2. Abra o BeastEmu da pasta de desenvolvimento. Em **Biblioteca → Adicionar jogos GB/GBC/GBA**, selecione a demonstração. O filtro **Game Boy Advance** mostra **BEAST INPUT**.
3. Selecione **Jogar → Iniciar teste**. A imagem vermelha tem dez faixas de 16 linhas. Cada faixa fica verde enquanto o botão correspondente estiver pressionado. De cima para baixo a ordem é A, B, Select, Start, direita, esquerda, cima, baixo, R e L. A demonstração sintetiza um tom de teste.
4. Teste volume, mudo, janela, tela cheia, perda de foco e saída. Em uma nova sessão as faixas começam soltas. Cartuchos GBA ficam fora do seletor de Link Cable.

## Núcleo e procedência

| Item | Valor |
|---|---|
| Binário | `cores/windows/mgba_libretro.dll`, PE AMD64, API Libretro 1 |
| Versão informada pela DLL | `0.11-212-7a12d6d` |
| Revisão completa incorporada ao binário | `7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6` |
| Aquisição | Buildbot Libretro, nightly Windows x86_64 obtida em 23/11/2026 |
| SHA-256 do ZIP de origem | `D9F6D58C47CCE9BE5DB69DFCFC9272B2DD6CC0BA051A5041129067A018EB7369` |
| SHA-256 da DLL | `AAD5891C91611C226A864E3D308E791038C862CA7E3A06491E6AA2B11BBC792F` |
| Importações PE diretas | KERNEL32.dll, msvcrt.dll, ole32.dll, SHELL32.dll e SHLWAPI.dll |
| Medição com a ROM de teste | 240 × 160, RGB565, 59,7275009 quadros/s, PCM estéreo de 65.536 Hz |

O endereço nightly é móvel. Para reconstruir, use o ZIP que corresponda ao hash acima e extraia a DLL em `cores/windows/`. O auxiliar e o empacotador verificam o hash da DLL. Coloque nesse mesmo diretório a DLL SameBoy aprovada, como indicado no README. Execute `flutter pub get`, `flutter build windows` e `dart run tool/package_windows.dart`. A última linha indica a pasta autônoma de desenvolvimento. Ela inclui os dois núcleos, os três auxiliares e XAudio2. Para executar os testes contra esses binários, aponte `BEASTEMU_TEST_PACKAGE` para essa pasta e execute `flutter test --concurrency=1`.

[ZIP original no Buildbot](https://buildbot.libretro.com/nightly/windows/x86_64/latest/mgba_libretro.dll.zip) · [Fonte correspondente à DLL](https://github.com/libretro/mgba/tree/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6) · [Projeto mGBA](https://github.com/mgba-emu/mgba) · [Documentação Libretro](https://docs.libretro.com/library/mgba/)

## Execução e persistência

O importador calcula o SHA-256 do conteúdo. A extensão .gba seleciona um processo mGBA próprio. O auxiliar verifica a identidade do cartucho e a ABI, carrega o conteúdo em memória e consulta a geometria e o relógio de emulação depois de carregar a ROM. A sessão usa o BIOS livre integrado ao núcleo. O comando de diretório de firmware externo está desabilitado.

No protocolo de vídeo GBA, os primeiros quatro bytes contêm largura e altura em uint16 little-endian. Seguem quadros RGBA8888 sem padding. O auxiliar converte usando o formato e o pitch do callback. Limita as dimensões e mantém no máximo um envio pendente. O caminho inverso envia a máscara de 16 botões. O frontend GB/GBC conserva seu protocolo. O áudio usa a taxa anunciada em uma voz XAudio2 própria e compartilha a fila limitada do backend Windows.

As preferências e a biblioteca de desenvolvimento ficam em `%APPDATA%\BeastEmu\BeastEmu GBA Dev`. O auxiliar SameBoy iniciado por esse aplicativo recebe uma raiz de dados de desenvolvimento em `%LOCALAPPDATA%\BeastEmu-GBA-Dev`. O auxiliar GBA não chama o gerenciador de cartuchos ou de estados do SameBoy.

Depois de `retro_load_game`, a DLL fornece um ponteiro de SAVE_RAM com até 131.072 bytes, inicialmente preenchidos com FF. O primeiro `retro_run` associa esse buffer ao cartucho. O auxiliar restaura somente os bytes validados antes desse primeiro quadro e consulta novamente ponteiro e tamanho entre quadros. Um buffer inicial de 128 KiB também pode representar autodetecção. A gravação só ocorre após mudança de conteúdo. Uma EEPROM pode crescer de 512 B para 8 KiB e a Flash de 64 para 128 KiB ao acessar outro banco. O auxiliar preserva o save maior se o jogo ainda não o identificou por completo. [Implementação da revisão](https://github.com/libretro/mgba/blob/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6/src/platform/libretro/libretro.c)

Cada ROM tem um diretório em `%LOCALAPPDATA%\BeastEmu-GBA-Dev\BeastEmu\saves\mgba\<SHA-256 da ROM>\`. O índice `cart.json` identifica a imagem atual e a anterior. Cada arquivo `<SHA-256 do conteúdo>.sav` contém os bytes brutos do cartucho no tamanho detectado. Para fazer backup, feche a sessão e copie a pasta inteira. Cópias idênticas e arquivos renomeados usam o mesmo diretório. A sessão mantém um bloqueio exclusivo até o fechamento. O auxiliar confere alterações a cada 300 quadros (aproximadamente cinco segundos) e ao sair. Escreve e verifica a imagem temporária antes de publicar o índice por renomeação no mesmo volume. Uma interrupção pode deixar um arquivo temporário ou uma imagem sem referência. Ao reabrir, vale a última geração confirmada pelo índice.

Um save inválido, uma alteração externa ou um tamanho incompatível gera um erro. Preserve a pasta para recuperação. Para restaurar um backup da pasta, primeiro feche todas as sessões e guarde uma cópia dos arquivos atuais. Buffers totalmente FF ou zero nunca substituem progresso válido. Esse cuidado também impede a persistência de um apagamento integral intencional do cartucho. O RTC do GBA não tem região independente exposta por esta DLL. A validação cobre os dados EEPROM, SRAM e Flash. Consulte abaixo o comportamento dos estados GBA.

### Conferir o progresso com um cartucho de teste

Na raiz desta cópia, execute `dart test/support/gba_save_rom.dart 32768 build/Progresso-SRAM.gba` com um destino novo. Os outros tamanhos aceitos são 512, 8192, 65536 e 131072. Importe o arquivo e inicie o jogo. Vermelho significa que o cartucho ainda não contém o marcador. Pressione A para gravar. O programa lê o marcador e pinta a tela de verde. Saia da sessão, feche o BeastEmu, abra novamente e entre no jogo. A tela deve ficar verde antes de pressionar qualquer botão. Com um homebrew que ofereça menu de save, guarde uma posição identificável pelo próprio menu e confira essa posição após reiniciar.


## Estados GBA

Durante o jogo, **Salvar estado** e **Carregar estado** abrem os cinco slots por ROM, com data e horário e confirmação de substituição. F5 salva o estado rápido e F9 carrega. As teclas seguem as preferências já existentes em Configurações e respeitam os mapeamentos personalizados. Uma tecla mantida pressionada executa a ação uma vez. O arquivo rápido é independente dos cinco slots.

Os arquivos ficam em `%LOCALAPPDATA%\BeastEmu-GBA-Dev\BeastEmu\states\mgba\<SHA-256 da ROM>\`, com nomes `1.state` a `5.state` e `quick.state`. O formato BGA1 identifica ROM, DLL, versão mGBA, slot, horário UTC, comprimentos e checksum SHA-256. A escrita usa temporário verificado e renomeação. Arquivos incompatíveis são preservados. O menu recusa sobrescrevê-los.

Nesta revisão, `retro_serialize_size` pode variar com a memória detectada. `retro_serialize` inclui SAVEDATA e RTC, enquanto `retro_unserialize` chama o carregador com RTC. Por isso o BeastEmu armazena também uma cópia explícita da memória de cartucho e a repõe após restaurar o estado nativo. Os testes exercitam a DLL local com cartuchos ARM sintéticos. A compatibilidade exige a mesma DLL e versão. [Fonte correspondente](https://github.com/libretro/mgba/blob/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6/src/platform/libretro/libretro.c)

Antes de carregar um estado válido, o auxiliar confirma o save normal atual e suspende a gravação periódica e final do cartucho até encerrar a sessão. O aviso **Cartucho protegido** permanece visível. Guarde os avanços dessa sessão nos slots ou no estado rápido. Ao reabrir normalmente o jogo, o cartucho retoma o save normal preservado. Para continuar a outra linha de progresso, carregue seu estado novamente. Aceleração e multiplayer GBA continuam fora desta etapa.

Para validar manualmente, salve pelo menu do jogo, crie um slot, avance e carregue o slot. Confira imagem, controles e áudio. Guarde um novo estado após avançar, feche completamente o aplicativo e reabra. Confira tanto o save normal quanto a recuperação do estado. Repita em tela cheia e com F5/F9.

## Créditos

mGBA © 2013–2026 Jeffrey Pfau, MPL 2.0. O diretório de fontes inclui `docs/mGBA-LICENSE.txt` e `docs/mGBA-inih.txt`. No build de desenvolvimento, os avisos acompanham a DLL em `licenses/mGBA.txt` e `licenses/mGBA-inih.txt`. O upstream atribui inih a Ben Hoyt (BSD de três cláusulas) e identifica LZMA SDK, MurmurHash3, getopt para MSVC e SQLite3 como domínio público. A lista de componentes do upstream abrange diferentes configurações de compilação. O programa ARM e o gerador usados nos testes são código original desta branch, sob a MIT do BeastEmu. Os testes dispensam cartuchos comerciais e imagens de firmware proprietário. [Atribuições do núcleo](https://github.com/libretro/mgba/blob/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6/README.md#copyright)
