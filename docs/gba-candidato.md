# BeastEmu GB/GBC/GBA · candidato local de desenvolvimento

Registro histórico da GBA 05. A preparação pública seguinte está no [guia da beta 0.2](beta-0.2.md), com identidade e caminhos públicos próprios.

Este candidato integra SameBoy para GB/GBC e mGBA para GBA no Windows x64. O proprietário aprovou manualmente a GBA 04. A compatibilidade de jogos comerciais específicos depende dos resultados registrados pelo avaliador. Versão técnica preservada `0.1.1-beta.1+3`. Proposta para futura inclusão pública de GBA `0.2.0-beta.1`, sujeita à autorização do proprietário.

Abra `beastemu.exe` mantendo toda a pasta. O instalador usa o nome **BeastEmu GBA Dev**, AppId `{04248C8D-1988-4CC3-A2EC-83D97B4A7A35}` e `%LOCALAPPDATA%\Programs\BeastEmu GBA Dev`. Os atalhos possuem esse nome. O instalador requer Visual C++ v14 x64 e permanece sem assinatura Authenticode. A validação de instalação e desinstalação deste candidato deve ocorrer em uma conta Windows descartável.

O portátil usa os mesmos perfis do instalador de desenvolvimento. Biblioteca, capas, favoritos, recentes e preferências ficam em `%APPDATA%\BeastEmu\BeastEmu GBA Dev`. Os dados dos auxiliares ficam em `%LOCALAPPDATA%\BeastEmu-GBA-Dev\BeastEmu`.

| Dados | Dentro da pasta de dados dos auxiliares |
|---|---|
| Cartucho SameBoy | `saves/<SHA-256>.cart` |
| Estados SameBoy | `states/<SHA-256>/{1..5,quick}.state` |
| Link Cable GB/GBC | `saves/link/p1` e `saves/link/p2` |
| Cartucho mGBA | `saves/mgba/<SHA-256>/cart.json` e imagens `.sav` por hash |
| Estados mGBA | `states/mgba/<SHA-256>/{1..5,quick}.state` |

Os formatos `.cart`, os índices de imagens GBA e os formatos de estados BST1/BGA1 têm verificações de identidade distintas. Estados dependem da DLL correspondente. Após carregar estado, preserve os novos avanços nos slots ou no estado rápido. O save normal fica protegido até encerrar a sessão. Copie a pasta inteira do cartucho mGBA ao fazer backup.

## Plano de integração futura dos perfis

A beta pública usa `%LOCALAPPDATA%\BeastEmu` e o perfil de suporte próprio, sem o prefixo de desenvolvimento. Nesta etapa não há migração de dados pessoais. A futura migração deverá ser opcional, com os dois aplicativos fechados, backup completo e inventário de hashes antes de copiar. Valide ROM, formato, checksum e DLL de cada estado. Preserve os namespaces por núcleo e por jogador. Para cada conflito, mantenha origem e destino e solicite escolha do proprietário. Não substitua dados válidos automaticamente. Faça a cópia em uma pasta intermediária, valide os hashes e publique o diretório confirmado. Registre o manifesto da operação. O rollback restaura o backup e mantém a origem. A biblioteca deve conservar SHA-256, favoritos e capas, com ajuste explícito dos caminhos das cópias importadas. Valide primeiro com cartuchos sintéticos e perfis descartáveis.

## Avaliação manual pendente

Use somente cópias legítimas já disponíveis. Registre jogo, região/revisão, hash da ROM, tipo de save identificado, máquina e resultado. Nenhum dos exemplos abaixo representa uma nova declaração de compatibilidade.

- Pokémon Ruby/Sapphire/Emerald, se disponíveis, para progresso, Flash e funções de relógio. Confira horário após fechar e reabrir. A persistência RTC GBA além de estados requer avaliação específica.
- Um jogo ou homebrew EEPROM 512 B e outro EEPROM 8 KiB. Salve uma posição identificável e recupere após reiniciar.
- Um cartucho SRAM e cartuchos Flash 64/128 KiB. Compare progresso antes e depois de acelerar e de carregar estados.
- Um jogo de ação, como Metroid ou Mario, se disponível, para movimento, resposta e áudio.
- Um jogo com uso frequente de L/R, como Mario Kart ou F-Zero, se disponível, para teclado e XInput.
- Alterne GB, GBC e GBA. Confira filtros, capas, favoritos, recentes e ausência de sessões antigas após sair.
- Teste as quatro velocidades, Tab pressionado/solto e perda de foco, mudo, volume e retorno a 1×. Avalie estalos e atraso.
- Teste cinco slots, confirmação de substituição, rápido F5/F9, tela cheia, fechamento completo e reabertura. Confira o save normal preservado.
- Em conta descartável, instale lado a lado com a beta, atualize este candidato, desinstale e reinstale. Compare hashes dos dados de teste e confira atalhos. Registre quaisquer avisos do Windows.

O código autoral permanece MIT em `LICENSE`. A marca tem política própria em `MARCA.md`. SameBoy, mGBA, Flutter, Dart e outros componentes conservam seus avisos em `licenses`. A origem fixa do mGBA está em `licenses/mGBA-FONTES.md`. O pacote inclui três auxiliares, os dois núcleos e a saída de áudio nativa. ROMs e firmware comerciais são fornecidos pelo usuário.
