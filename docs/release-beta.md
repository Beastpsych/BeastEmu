# BeastEmu para Windows x64 · notas da primeira beta

Rascunho para revisão do proprietário. Os arquivos avaliados abaixo identificam-se como **0.1.1-beta.1+3**.

O BeastEmu é um emulador gratuito de Game Boy e Game Boy Color com interface em português. Importe seus próprios arquivos GB/GBC, organize a biblioteca por favoritos ou jogos recentes e escolha **Jogar**. As capas podem ser escolhidas no computador. Os pacotes não contêm jogos.

## Durante a partida

- Ouça o jogo em estéreo, ajuste o volume, alterne o mudo e jogue em janela ou tela cheia. A imagem mantém a proporção do cartucho.
- Use teclado remapeável ou um controle Xbox compatível com XInput. O acelerador oferece 1×, 2×, 3× e 4×. Segurar Tab aplica 4× temporariamente. A aceleração silencia o áudio e a velocidade efetiva depende do computador.
- Salve pelo menu do jogo para preservar SRAM e relógio RTC nos cartuchos compatíveis. Há também cinco slots manuais por ROM e um slot rápido independente. F5 salva e F9 carrega. Depois de carregar um estado, guarde o progresso dessa sessão nos slots. Ao reabrir, o jogo retoma o save normal de cartucho.
- **Link Cable Local** é experimental. Ele exibe dois Game Boys sincronizados no mesmo PC, com controles e saves separados por jogador. A comunicação serial foi verificada com cartuchos sintéticos. A troca de Pokémon em jogos reais permanece sem resultado documentado. O modo dual opera em 1×. Os save states ficam disponíveis no modo individual.

## Instalação e atualização

Use Windows 10 ou 11 x64 com o runtime Microsoft Visual C++ v14 x64 compatível. O **Setup** instala por usuário, cria o atalho no menu Iniciar e oferece um atalho na área de trabalho. Para usar o **portátil**, extraia o ZIP inteiro e abra `beastemu.exe`. As duas formas usam os dados da mesma conta Windows. Ao mover o portátil para outro computador, leve também o backup dos dados.

Feche a sessão por **Sair** e encerre o aplicativo antes de atualizar sobre uma instalação anterior. A desinstalação conserva os dados da conta. A documentação identifica as pastas do perfil atual, do perfil legado e dos saves. O instalador está sem assinatura Authenticode e o SmartScreen pode alertar sobre um aplicativo desconhecido. [Instalar, atualizar e fazer backup](windows-instalador.md) · [Guia do portátil e dos controles](windows-portatil.md)

## Arquivos avaliados

| Arquivo | SHA-256 |
|---|---|
| `BeastEmu-0.1.1-beta.1+3-Windows-x64-Setup.exe` | `CC90800526B38014AD820A9BDCCA4F409C715886066F4520F6339C55174C12AE` |
| `BeastEmu-0.1.1-beta.1+3-Windows-x64-Portable.zip` | `94AE1D5193BE338F791DF96CAFD7A5B9707672121EF6B85F60A9753D8764AC09` |

Confira o download com `Get-FileHash -Algorithm SHA256 -LiteralPath <arquivo>`. O arquivo `SHA256SUMS.txt` contém as duas somas. Uma nova compilação, assinatura ou alteração de versão exige a substituição destes valores pelos hashes dos arquivos efetivamente publicados.

O proprietário relatou testes manuais bem-sucedidos do candidato anterior em dois PCs Windows. A atualização RC2 → beta tem um [roteiro próprio](validacao-rc2.md). Os testes de desenvolvimento usam ROMs sintéticas. O código autoral do BeastEmu é distribuído sob MIT, com o aviso `Copyright (c) 2026 Beast`. A origem do emblema e do logotipo e as permissões pendentes para redistribuição das artes estão no [guia da marca](../design/README.md). A emulação utiliza o núcleo SameBoy com integração Libretro e a interface utiliza Flutter e Dart. [Licença do projeto](../LICENSE) · [Créditos e avisos de terceiros](terceiros.md) · [Histórico de alterações](../CHANGELOG.md)
