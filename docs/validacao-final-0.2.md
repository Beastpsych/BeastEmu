# Validação final do candidato 0.2

O proprietário confirmou dez testes manuais, abrangendo GB/GBC/GBA, Pokémon FireRed e Emerald, controles, saves, estados, áudio, RTC, aceleração e testes externos. Este registro reproduz a confirmação do proprietário. Não foram fornecidos registros individuais com revisões das ROMs e máquinas, portanto não se atribuem esses resultados a versões específicas dos cartuchos ou a hardware determinado.

## Ciclo de instalação pendente

Na conferência deste ambiente, Windows Sandbox e ferramentas de VM não estavam disponíveis. Os caminhos conhecidos de dados resolvem para o perfil do proprietário. Os instaladores não foram executados sobre essa instalação. O upgrade real 0.1.1 → 0.2, seguido de desinstalação e reinstalação, permanece sem aprovação. Os testes automatizados de preservação e importação usam somente dados temporários e cartuchos sintéticos.

O script `tool/test_windows_installer.ps1` é um smoke test de arquivos, registro, atalhos e janela. Ele usa marcadores, exige uma conta descartável e recusa um perfil que já contenha BeastEmu. Seus marcadores não comprovam leitura de progresso real dentro dos jogos. O roteiro abaixo deve complementar esse teste.

1. Preparar uma VM Windows x64 ou conta descartável limpa, com o runtime Visual C++ exigido. Registrar o ambiente e obter os instaladores 0.1.1 e 0.2, conferindo os hashes. Não usar a conta pessoal.
2. Instalar 0.1.1. Importar cartuchos sintéticos GB e GBC gerados pelos testes do projeto. Criar favorito, recente, capa local, configurações, remapeamentos e dados de gamepad de teste. Salvar progresso identificável no cartucho, em um slot manual e no rápido. Confirmar leitura após reabrir a versão antiga.
3. Fechar o programa, copiar integralmente os diretórios públicos de dados e quaisquer diretórios legados referenciados. Registrar caminho, tamanho e SHA-256 de cada arquivo. Guardar o backup fora da instalação.
4. Preparar dados sintéticos separados de GBA Dev e registrar seus hashes, instalação e AppId. Instalar 0.2 sobre a pública. Antes de jogar, comparar os arquivos de dados com o inventário. Conferir versão, AppId público, pasta de instalação e atalhos. GBA Dev deve conservar seu registro e seus dados.
5. Reabrir GB e GBC, conferir o progresso normal e restaurar os estados manual e rápido. Conferir SRAM e RTC com os cartuchos de teste apropriados. Verificar biblioteca, capas, favoritos, recentes, teclado, gamepad e preferências. Distinguir alterações legítimas feitas ao jogar das verificações anteriores à execução.
6. Importar cartuchos sintéticos GBA de EEPROM 512 B/8 KiB, SRAM e Flash 64/128 KiB. Salvar e recuperar o progresso após fechar. Conferir slots, rápido, áudio, 1×–4×, Tab, foco, L/R, mudo e tela cheia. Verificar ausência de auxiliares após encerrar.
7. Seguir o procedimento opcional de `beta-0.2.md` com dados descartáveis do GBA Dev. Exercitar conflito, recusa de arquivo corrompido, preservação da origem e restauração do backup.
8. Fechar tudo e registrar novo inventário e backup. Desinstalar a pública 0.2, conferir preservação dos dados públicos e do GBA Dev e remoção dos arquivos de programa e atalhos públicos. Reinstalar a mesma 0.2 e conferir dados e leitura do progresso.
9. Registrar logs, hashes antes/depois, resultados de cada passo e problemas. O ciclo só pode ser declarado aprovado depois dessa execução. Os testes externos informados pelo proprietário não identificam esse ciclo específico de atualização.

## Publicação após autorização

A branch local é `release/0.2.0-beta.1`. O histórico público e a tag `v0.1.1-beta.1` devem permanecer preservados. Nenhum comando desta seção foi executado nesta preparação.

Depois de concluir o ciclo pendente e receber autorização explícita, usar GitHub CLI autenticado como Beastpsych. Executar em `E:\dev\beastemu-0.2`, verificar árvore limpa, os hashes dos artefatos finais e a main remota mais recente.

```powershell
gh auth status
git fetch origin
git push origin release/0.2.0-beta.1
gh pr create --base main --head release/0.2.0-beta.1 --title "BeastEmu 0.2.0-beta.1 com GB/GBC/GBA" --body-file docs/release-0.2.md
```

Revisar o PR e resolver qualquer alteração remota posterior antes de integrar. Após aprovação do PR e autorização para atualizar main, fazer merge preservando o histórico. Não usar squash se o objetivo for conservar os commits GBA integrados. Registrar o número real do PR e o SHA aprovado.

```powershell
gh pr merge <numero-do-PR> --merge
git fetch origin
git rev-parse origin/main
```

Conferir que o SHA retornado corresponde ao merge aprovado e que a tag futura ainda não existe. Substituir o marcador abaixo somente por esse SHA, criar a tag anotada e enviá-la.

```powershell
git tag -a v0.2.0-beta.1 <SHA-aprovado> -m "BeastEmu v0.2.0-beta.1"
git push origin refs/tags/v0.2.0-beta.1
```

Com a pasta de artefatos finais em `$artifacts`, publicar a pré-release com seus três anexos. Confirmar que as notas contêm os hashes atuais e que os links apontam para a tag correta.

```powershell
gh release create v0.2.0-beta.1 --verify-tag --prerelease --title "BeastEmu v0.2.0-beta.1 para Windows x64" --notes-file docs/release-0.2.md "$artifacts/BeastEmu-0.2.0-beta.1+4-Windows-x64-Setup.exe" "$artifacts/BeastEmu-0.2.0-beta.1+4-Windows-x64-Portable.zip" "$artifacts/SHA256SUMS.txt"
```

Confirmar a classificação pre-release e os três anexos. Baixar novamente os pacotes para uma pasta nova, conferir seus SHA-256 e testar os links das notas, README, LICENSE e MARCA.md. Conferir que a release 0.1.1 conserva seus anexos e tag. A descrição sugerida para o repositório é “Emulador open-source de Game Boy, Game Boy Color e Game Boy Advance para Windows x64”. Topics sugeridos são `gameboy`, `gameboy-color`, `gameboy-advance`, `emulator`, `flutter`, `windows` e `libretro`. Sua alteração remota depende da autorização de publicação.
