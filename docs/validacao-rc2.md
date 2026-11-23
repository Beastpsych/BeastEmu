# Testar a atualização do RC2 para a primeira beta

Use uma VM ou conta Windows x64 descartável. Registre a edição do Windows, a versão de origem `0.1.0-beta.rc.2+2`, a versão de destino `0.1.1-beta.1+3` e o SHA-256 dos dois instaladores. Trabalhe com cartuchos sintéticos e dados de teste. O teste automatizado de instalação precisa de um perfil vazio.

1. Instale o RC2, abra pelo menu Iniciar e importe uma ROM sintética com bateria e relógio. Configure capa, favorito, volume, teclado e XInput. Gere progresso no cartucho, um estado manual e um rápido. Se testar Link Cable, gere progresso separado para J1 e J2.
2. Saia do jogo por **Sair** e feche o aplicativo. Copie as pastas de saves, estados e perfis para um backup fora da instalação. Registre os hashes dos arquivos de cartucho e dos estados, o slot, o horário do relógio e as preferências. Os caminhos por tipo de dado estão no [guia do instalador](windows-instalador.md#atualizar-e-desinstalar).
3. Instale a beta sobre o RC2 na mesma conta. Antes de iniciar um jogo, compare os hashes com os do passo 2. Verifique uma única entrada BeastEmu em Aplicativos instalados, versão numérica `0.1.1.3` nas propriedades do executável e ícone correto nos dois atalhos quando o de desktop estiver selecionado.
4. Abra pelo menu Iniciar. Confira a versão em **Sobre**, a biblioteca, a capa, o favorito, o volume, o teclado e o gamepad. Continue pelo save interno e confira o avanço do RTC pelo intervalo decorrido. Depois carregue os dois estados de teste. Confira a indicação de proteção e reabra o jogo para verificar o progresso normal do cartucho.
5. Em Link Cable, mantenha a ROM em cada posição original. Verifique as duas telas, as entradas independentes e o encerramento. Confira também o retorno do áudio ao passar de 4× para 1× na sessão individual.
6. Feche tudo, registre novos hashes e desinstale pela lista de aplicativos do Windows. Confira a remoção do programa e dos atalhos e compare novamente os arquivos de dados com esses últimos hashes. Reinstale e retome a partida. Registre qualquer diferença junto à etapa em que ocorreu.

Para o ensaio automatizado, em um segundo perfil descartável vazio, coloque `payload.json` ao lado do Setup da beta e execute o comando abaixo em PowerShell x64. O script cria dados sentinela e verifica instalação, atualização, atalhos, abertura, reinstalação e desinstalação. A retomada do jogo e o avanço do relógio são verificações adicionais do roteiro acima.

```powershell
$rc2 = Read-Host 'Caminho do Setup RC2'
$beta = Read-Host 'Caminho do Setup da beta'
./tool/test_windows_installer.ps1 -PreviousInstaller $rc2 -Installer $beta -DisposableProfile
```
