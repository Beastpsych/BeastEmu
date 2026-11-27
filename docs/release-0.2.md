# BeastEmu v0.2.0-beta.1 para Windows x64

Rascunho local de pré-release. Build `0.2.0-beta.1+4`, versão Windows `0.2.0.4`. A publicação depende da aprovação final do proprietário.

- Integra Game Boy e Game Boy Color via SameBoy e Game Boy Advance via mGBA Libretro.
- Oferece biblioteca unificada, capas locais, favoritos e recentes, teclado/XInput com L/R GBA, áudio estéreo, tela cheia e aceleração 1×–4×.
- Guarda cartuchos GBA EEPROM/SRAM/Flash e cinco estados manuais mais um rápido por ROM. Após carregar estado, o cartucho normal fica protegido até reabrir a sessão.
- Preserva os caminhos públicos, o AppId e os formatos GB/GBC da beta anterior. A importação do GBA Dev é opcional, manual, precedida de backup e auditoria de integridade.
- Mantém Link Cable Local experimental para GB/GBC. GBA opera em modo individual.

O instalador não possui assinatura Authenticode. As distribuições não incluem ROMs comerciais nem BIOS proprietário. O código autoral usa MIT, a marca segue política própria e mGBA conserva MPL 2.0 com identificação da revisão e dos fontes correspondentes.

Consulte o [guia de atualização e importação](https://github.com/Beastpsych/BeastEmu/blob/v0.2.0-beta.1/docs/beta-0.2.md), os [créditos](https://github.com/Beastpsych/BeastEmu/blob/v0.2.0-beta.1/docs/terceiros.md), a [licença MIT](https://github.com/Beastpsych/BeastEmu/blob/v0.2.0-beta.1/LICENSE) e a [política de marca](https://github.com/Beastpsych/BeastEmu/blob/v0.2.0-beta.1/MARCA.md). Esses links ficam disponíveis quando a tag aprovada for publicada.

O proprietário confirmou dez testes manuais, incluindo GB/GBC/GBA, Pokémon FireRed e Emerald, controles, saves, estados, áudio, RTC, aceleração e testes externos. Esses resultados são informados pelo proprietário. O ciclo público específico de atualização 0.1.1 → 0.2, desinstalação e reinstalação permanece pendente de execução em ambiente descartável. A importação opcional de dados pessoais reais exige backup e autorização. Testes automatizados usam cartuchos sintéticos e dados temporários.

## Pacotes preparados localmente

| Arquivo | SHA-256 |
|---|---|
| `BeastEmu-0.2.0-beta.1+4-Windows-x64-Setup.exe` | `C038F92141668DCAFA1C91CCBC3978DC3FE279B65AF80B958836300158F838A8` |
| `BeastEmu-0.2.0-beta.1+4-Windows-x64-Portable.zip` | `BF2385CE45B4ACEBA794ABE45CE6A58BF8C675CBAB76C3A4FCE20572484ACA03` |

Recalcule essas somas se os arquivos forem recompilados ou assinados. O arquivo `SHA256SUMS.txt` acompanha os artefatos locais.

Validação local do candidato com análise Flutter limpa, compilação Windows concluída e 114 testes automatizados aprovados. Os testes incluem alternância GB/GBC/GBA, preservação de dados de perfil, cópia manual auditada do progresso GBA, recusa de arquivos corrompidos, estados, aceleração e regressão GB/GBC. A integridade do ZIP foi conferida por tamanho e SHA-256 de cada entrada. Essa validação automatizada complementa o checklist manual pendente acima.
