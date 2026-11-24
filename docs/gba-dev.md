# Game Boy Advance experimental · Windows x64

Este build local usa um perfil de desenvolvimento. Importe somente cartuchos sintéticos ou homebrew de teste. **O progresso GBA se perde ao fechar o jogo.** A sessão individual mantém o teclado configurado e aceita direcional, A, B, Start e Select. Q e E acionam L e R quando livres de outros mapeamentos. No controle XInput, use LB e RB. A janela preserva a proporção, permite ajustar volume ou mudo e encerra o auxiliar ao sair.

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

Na demonstração, `retro_get_memory_size(SAVE_RAM)` anunciou 131.072 bytes logo após a carga e RTC anunciou zero. O fonte da revisão retorna esse máximo enquanto o tipo está em autodetecção. A persistência futura precisa acompanhar EEPROM (512 B / 8 KiB), SRAM e Flash (64 / 128 KiB), o tamanho efetivamente detectado e os periféricos do cartucho. O plano é usar uma pasta `saves/mgba/<sha256>/` no perfil de desenvolvimento, identificar formato e tamanho, testar restauração após reiniciar e gravar atomicamente com proteção contra colisão de sessões. O arquivo .cart do SameBoy tem formato próprio. Save states, aceleração e multiplayer GBA ficam fora deste marco. [Implementação Libretro da revisão](https://github.com/libretro/mgba/blob/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6/src/platform/libretro/libretro.c)

## Créditos

mGBA © 2013–2026 Jeffrey Pfau, MPL 2.0. O diretório de fontes inclui `docs/mGBA-LICENSE.txt` e `docs/mGBA-inih.txt`. No build de desenvolvimento, os avisos acompanham a DLL em `licenses/mGBA.txt` e `licenses/mGBA-inih.txt`. O upstream atribui inih a Ben Hoyt (BSD de três cláusulas) e identifica LZMA SDK, MurmurHash3, getopt para MSVC e SQLite3 como domínio público. A lista de componentes do upstream abrange diferentes configurações de compilação. O programa ARM e o gerador usados nos testes são código original desta branch, sob a MIT do BeastEmu. Os testes dispensam cartuchos comerciais e imagens de firmware proprietário. [Atribuições do núcleo](https://github.com/libretro/mgba/blob/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6/README.md#copyright)
