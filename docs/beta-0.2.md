# Candidato BeastEmu 0.2.0-beta.1

Flutter `0.2.0-beta.1+4`, Windows `0.2.0.4`. Tag futura proposta `v0.2.0-beta.1`. A beta pública 0.1.1 permanece preservada. O proprietário informou aprovação manual das etapas GBA. O upgrade público deste candidato, sua instalação e seu uso em outro computador ainda devem ser validados.

O instalador usa **BeastEmu**, AppId `{EA0278D8-06C3-4CE8-9AC3-0219910142EE}`, `%LOCALAPPDATA%\Programs\BeastEmu`, atalhos públicos e os ícones dracônicos. Ele atualiza a instalação pública anterior pelo mesmo registro. A instalação **BeastEmu GBA Dev** conserva AppId `{04248C8D-1988-4CC3-A2EC-83D97B4A7A35}` e pasta própria. O instalador permanece sem assinatura Authenticode e requer Visual C++ v14 x64.

## Dados e atualização

| Dados públicos | Caminho |
|---|---|
| Biblioteca, capas, preferências e controles | `%APPDATA%\BeastEmu\BeastEmu` ou diretório legado já usado pela instalação |
| Cartucho SameBoy | `%LOCALAPPDATA%\BeastEmu\saves\<SHA-256>.cart` |
| Estados GB/GBC | `%LOCALAPPDATA%\BeastEmu\states\<SHA-256>\` |
| Link Cable GB/GBC | `%LOCALAPPDATA%\BeastEmu\saves\link\p1` e `p2` |
| Cartucho mGBA | `%LOCALAPPDATA%\BeastEmu\saves\mgba\<SHA-256>\` |
| Estados GBA | `%LOCALAPPDATA%\BeastEmu\states\mgba\<SHA-256>\` |

O prefixo `BeastEmu-GBA-Dev` continua exclusivo do aplicativo de desenvolvimento e dos perfis temporários injetados pelos testes. O candidato público conserva empresa/produto BeastEmu e a lógica de localização e migração legada da beta 0.1.1. Os formatos BCAR1 de cartucho e BST1 de estados SameBoy e sua DLL `90e2899` são mantidos. O formato BGA1 e a DLL mGBA `7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6` também são mantidos. Os núcleos validam os dados por identidade, tamanho e checksum conforme seus respectivos formatos.

Antes de atualizar uma conta real, obtenha autorização e faça backup completo dos dados públicos, incluindo qualquer diretório legado referenciado pela biblioteca. Feche os dois aplicativos e compare hashes antes e depois do upgrade em conta descartável. A atualização substitui executáveis e conserva os dados fora da instalação. Após carregar estado, continue a guardar os avanços em slots ou no arquivo rápido até reabrir a sessão normal.

## Importação GBA Dev opcional e manual

Este candidato não inicia importação automática do perfil GBA Dev. O procedimento abaixo foi exercitado com cópias sintéticas, incluindo recusa de corrupção, incompatibilidade de núcleo e conflitos. Jogos e saves reais exigem backup e validação do proprietário.

1. Feche todas as sessões públicas e de desenvolvimento. Faça cópias integrais de `%LOCALAPPDATA%\BeastEmu` e `%LOCALAPPDATA%\BeastEmu-GBA-Dev\BeastEmu` para pastas de backup novas. Guarde também os perfis de `%APPDATA%`.
2. Importe a mesma ROM GBA na biblioteca pública pelo aplicativo. Verifique o SHA-256 do conteúdo. A biblioteca reconhece cópias idênticas, independentemente do nome. Capas e favoritos podem ser escolhidos novamente nessa entrada. Não substitua o JSON da biblioteca pública pelo JSON de desenvolvimento, pois seus caminhos e demais entradas pertencem a perfis diferentes.
3. Na cópia de fontes desta beta, com Dart disponível, execute `dart run tool/audit_gba_import.dart <ROM.gba> <raiz-origem-BeastEmu> <raiz-destino-BeastEmu>`. A raiz de origem usual é `%LOCALAPPDATA%\BeastEmu-GBA-Dev\BeastEmu` e a de destino é `%LOCALAPPDATA%\BeastEmu`. A ferramenta somente lê arquivos. Ela valida índice, imagens `.sav`, ROM, DLL, revisão, slots e SHA-256, e lista cada arquivo como NOVO ou CONFLITO. Dados recusados permanecem na origem.
4. Para arquivos NOVO, copie manualmente somente os arquivos listados, mantendo os caminhos relativos. O cartucho mGBA exige `cart.json` e todas as imagens que ele referencia, incluindo a geração anterior. Estados ficam na pasta separada `states/mgba/<SHA-256>`. Arquivos `.lock`, temporários e imagens órfãs ficam fora da cópia.
5. Em qualquer CONFLITO, preserve as duas pastas e escolha explicitamente qual conjunto completo usar. A opção conservadora é conservar o destino público e cancelar a cópia daquela ROM. Para escolher o progresso de desenvolvimento, primeiro mova a pasta inteira de destino daquela ROM para um backup novo. Em seguida copie o conjunto completo validado. Evite combinar índices de uma origem com imagens de outra. Registre sua escolha e os hashes. A ferramenta não escolhe nem sobrescreve arquivos.
6. Execute novamente a auditoria com a pasta pública como origem e confira hashes iguais aos do inventário escolhido. Abra a ROM normalmente, verifique o progresso do cartucho e teste os slots em separado. Confira horário quando aplicável. O RTC GBA além da memória de cartucho continua sujeito à avaliação por jogo.
7. Se falhar, feche o aplicativo, preserve a tentativa em outra pasta e restaure o backup completo do destino. A origem GBA Dev permanece disponível para recuperação. Não apague os backups antes da validação final.

O procedimento importa o progresso por ROM. A incorporação automática de biblioteca, capas e preferências do GBA Dev fica adiada. A biblioteca pública existente continua sendo o catálogo principal.

## Checklist do proprietário

- Em conta de teste, instalar a beta pública 0.1.1, importar cartuchos sintéticos, salvar, criar slots, capas, favoritos, recentes e configurações. Fazer backup e inventário.
- Atualizar para 0.2, conferir a versão `0.2.0.4`, atalhos, ícones e os mesmos dados GB/GBC. Comparar o inventário antes de executar jogos que alterem legitimamente o progresso.
- Testar GB/GBC com áudio, RTC, teclado e XInput. Conferir Link Cable Local experimental somente em GB/GBC.
- Testar GBA com EEPROM 512 B/8 KiB, SRAM e Flash 64/128 KiB. Verificar save interno, cinco slots, rápido F5/F9, aceleração e retorno a 1×, mudo, L/R, foco e tela cheia.
- Exercitar a importação opcional com cópias descartáveis, conflito e rollback. Só depois avaliar dados reais com autorização e backups.
- Desinstalar e reinstalar em conta descartável. Conferir que os dados persistem e que GBA Dev continua independente.
- Repetir em outro computador. Registrar título, região/revisão, hash da ROM, tipo de save, hardware, áudio, RTC e desempenho. Usar somente cópias legítimas já disponíveis.

Os testes sintéticos continuam separados da validação comercial. O proprietário confirmou dez testes manuais, incluindo Pokémon FireRed e Emerald, GB/GBC/GBA, controles, saves, estados, áudio, RTC, aceleração e testes externos. As revisões dos cartuchos e as máquinas não foram individualizadas. As capturas existentes no README documentam a beta 0.1. O ciclo público de upgrade, desinstalação e reinstalação permanece pendente por indisponibilidade de ambiente descartável nesta preparação. Consulte [o registro final](validacao-final-0.2.md).
