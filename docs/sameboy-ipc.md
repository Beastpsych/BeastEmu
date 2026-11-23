# Comunicação com o processo SameBoy

O socket TCP em loopback envia quadros RGBA de 160 × 144 do auxiliar ao Flutter. No sentido inverso, cada máscara do jogador 1 ocupa dois bytes em little-endian. O fechamento do socket encerra a sessão e aciona a gravação final do cartucho.

O controle de volume usa o pipe de entrada padrão do processo filho. O Flutter define `BEASTEMU_VOLUME_V1` com o percentual inicial em decimal. O auxiliar aplica esse valor à voz XAudio2 antes do primeiro quadro. A ausência da variável mantém a compatibilidade com a execução autônoma a 100%.

Durante a sessão, cada byte de entrada entre 0 e 100 representa um percentual absoluto. Zero silencia a voz. Com o protocolo v1, o auxiliar ignora os bytes de 101 a 255. Quando vários comandos chegam juntos, vale o último percentual válido. O fim do pipe encerra a recepção de ajustes. A fila PCM continua sendo consumida mesmo com a voz silenciada.

No Windows x64, um isolate consulta `XInputGetState` na DLL de sistema `xinput1_4.dll` enquanto o painel de controles ou o jogo está aberto. A consulta dos dispositivos conectados usa um intervalo de 8 ms. A busca nas posições vazias ocorre a cada segundo. A zona morta do analógico esquerdo é de 7849 unidades por eixo. LT e RT contam como pressionados acima de 30.

As duas primeiras posições XInput conectadas, em ordem de índice, fornecem estados lógicos independentes para os jogadores 1 e 2. A sessão atual combina apenas o jogador 1 com o teclado por meio de `setDeviceButtons`. O auxiliar entrega essa máscara à porta 0 em `retro_input_state`. A perda de foco libera a entrada do jogo. Ao retomar o foco ou trocar de posição XInput, o controle precisa voltar ao repouso antes de enviar comandos.


## Estados e aceleração

As instruções desta seção se aplicam à sessão de um jogador.

O aplicativo habilita a extensão de comandos com `BEASTEMU_COMMANDS_V2=1`. Cada instrução continua ocupando um byte em stdin. O auxiliar usa stdout para confirmações de estados. O socket de vídeo mantém o formato anterior e permite apenas um quadro com envio pendente.

| Byte | Ação |
|---|---|
| 128 | Consultar cinco slots da ROM |
| 129–133 | Criar slot 1–5 vazio |
| 134–138 | Substituir slot 1–5 após confirmação |
| 139–143 | Restaurar slot 1–5 |
| 144–147 | Velocidades 1×, 2×, 3× e 4× |
| 148, 149 | Salvar ou carregar o slot rápido exclusivo da ROM |

O cliente aguarda uma linha com o prefixo `BEASTEMU_STATE ` e um objeto JSON com `command`, `protected` e, conforme a operação, `slots`, `empty` (slot rápido ausente) ou `error`. Mantém uma única operação de estado pendente. O auxiliar executa a operação entre quadros e confere a revisão do slot antes de carregar ou substituir. Em 2×, 3× e 4× ele consome o PCM gerado pelo núcleo e suspende o envio ao XAudio2. Ao voltar a 1× reaplica o volume corrente.

Quando a biblioteca dispõe do hash da importação, o auxiliar confere `BEASTEMU_EXPECTED_ROM_SHA256` com os mesmos bytes enviados à DLL antes de abrir o cartucho. Entradas antigas sem hash continuam usando o conteúdo carregado para identificar seus slots. O formato BST1 e os caminhos dos cinco slots foram preservados. O slot rápido usa `quick.state` e passa pelas mesmas verificações antes de carregar ou substituir. Arquivos incompatíveis ficam intactos.

Os slots ficam em `%LOCALAPPDATA%\BeastEmu\states\<SHA-256 da ROM>\`. Cada arquivo BST1 inclui o hash da ROM e da DLL, horário UTC, estado nativo e checksum SHA-256. Antes de restaurar, o auxiliar conclui a gravação normal do cartucho. A partir desse ponto, somente slots guardam progresso até reabrir o jogo. O bloqueio do cartucho permanece ativo até o encerramento.

## Link Cable Local experimental

O argumento `--link-local-v1 ROM1 ROM2 PORTA` seleciona o protocolo dual antes de abrir o socket. O auxiliar procura o subsistema `gb_link_2p` em `SET_SUBSYSTEM_INFO` e passa duas estruturas `retro_game_info` contíguas a `retro_load_game_special`. Cada chamada a `retro_run` avança os dois consoles dentro da mesma DLL. O núcleo conduz o relógio serial e entrega um quadro composto por ambas as telas. [Documentação oficial do SameBoy](https://docs.libretro.com/library/sameboy/#link)

Do auxiliar ao Flutter trafegam quadros RGBA de 320 × 144, com J1 à esquerda. No sentido inverso trafegam quatro bytes por atualização, primeiro a máscara de J1 e depois a de J2, ambas de 16 bits little-endian. O auxiliar só aplica pares completos às portas Libretro 0 e 1. Em stdin ele aceita volume. A sessão dual executa em 1× e usa o áudio estéreo de J1.

A DLL anuncia os tipos de SRAM `0x100` e `0x300` no descritor. Os RTCs são consultados diretamente pelos tipos `0x201` e `0x401`. Cada jogador tem um diretório próprio em `%LOCALAPPDATA%\BeastEmu\saves\link\p1` ou `p2`. Dentro dele, o hash SHA-256 da ROM identifica o arquivo BCAR v1. Cada arquivo mantém seu próprio bloqueio, checksum, checkpoint e gravação final.

Para reproduzir a prova, execute `flutter test --concurrency=1 test/sameboy_link_integration_test.dart`. Os programas MBC3 sintéticos armam o registrador SC com relógios externo e interno, leem SB ao fim da transferência e guardam o byte recebido na SRAM. O teste verifica os dois bytes, as mudanças de tela e o RTC em arquivos temporários. Uma segunda execução da mesma ROM nas duas portas confere a restauração por jogador.
