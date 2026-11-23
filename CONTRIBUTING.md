# Como contribuir

Para relatar uma falha, descreva a versão exibida em **Configurações → Sobre o BeastEmu**, a edição e arquitetura do Windows, o tipo de pacote, o modo de jogo e a sequência mínima para reproduzir. Indique o que esperava e o que aconteceu. Para falhas de controle ou áudio, inclua o modelo do dispositivo e o momento em que a falha ocorre. O relato pode ser escrito em português.

Use uma ROM sintética sempre que possível. Ao anexar uma captura ou um trecho de log, confira se ele expõe o nome da conta, caminhos da biblioteca ou dados de outra pessoa. ROMs comerciais, BIOS de terceiros, saves pessoais e credenciais devem ficar fora de issues e contribuições. Se o relato envolver dados sensíveis, combine um canal privado com o mantenedor antes de compartilhar detalhes.

Para alterar o código, prepare o ambiente Windows descrito no README, mantenha a mudança concentrada em um problema e use dados temporários nos testes. Execute `flutter analyze` e `flutter test --concurrency=1`. Para alterações nativas, de recursos ou distribuição, compile também com `flutter build windows`. Registre quais verificações foram automatizadas e quais foram feitas com hardware. [Compilação do projeto](README.md#compilar-no-windows) · [Protocolo e testes do SameBoy](docs/sameboy-ipc.md)
