# Histórico do BeastEmu

## 0.2.0-beta.1 · build 4 · candidato local

- Integra GB/GBC com SameBoy e GBA com mGBA Libretro.
- Acrescenta salvamento de cartucho EEPROM/SRAM/Flash GBA, cinco slots e estado rápido por ROM.
- Oferece áudio estéreo, L/R por teclado e XInput, aceleração 1×–4×, atalhos configuráveis e tela cheia no GBA.
- Preserva a biblioteca e os formatos de saves e estados GB/GBC da beta 0.1.1.
- Mantém o AppId público e a pasta de instalação. GBA Dev continua com identidade própria.
- Inclui avisos MPL 2.0 e identificação dos fontes do mGBA, roteiro de atualização e importação manual opcional com backup e validação.
- A validação manual do upgrade público e de outro computador está pendente. Link Cable Local permanece experimental e exclusivo de GB/GBC.

## 0.1.1-beta.1 · build 3

Primeira beta preparada para distribuição em Windows x64. O executável e o instalador usam a versão de produto `0.1.1-beta.1+3` e o recurso numérico `0.1.1.3`.

- Emulação de Game Boy e Game Boy Color com SameBoy Libretro, áudio XAudio2 e vídeo proporcional em janela ou tela cheia.
- Biblioteca com importação de ROMs, capas locais, filtros, favoritos e jogos recentes.
- Saves normais de cartucho, incluindo RTC quando disponível. Cinco slots manuais e um rápido por conteúdo de ROM, com proteção dos saves normais ao restaurar estados.
- Teclado e atalhos remapeáveis, XInput e aceleração em 1×, 2×, 3× e 4×.
- Link Cable Local experimental com telas e cartuchos independentes. Comunicação serial verificada com programas sintéticos.
- Instalador por usuário e portátil. A atualização sobre o RC2 conserva o identificador da instalação e os diretórios dos dados. O roteiro inclui conferência dos saves e do relógio após a atualização. [Teste de atualização](docs/validacao-rc2.md)
