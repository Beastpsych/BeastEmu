# Conferência da beta Windows

Esta é a primeira árvore preparada para publicação do BeastEmu. Ela foi exportada dos arquivos rastreados da versão aprovada e recebeu um histórico Git independente. O nome de versão é `0.1.1-beta.1+3`, com recurso numérico Windows `0.1.1.3`. Os nomes e hashes dos dois pacotes estão nas [notas de lançamento](release-beta.md).

## Escopo da conferência

- Conferir cada arquivo da exportação por hash Git e revisar as diferenças de versão, documentação e empacotamento antes do primeiro commit.
- Inspecionar nomes, conteúdo e metadados em busca de jogos, BIOS, saves, perfis, credenciais, caminhos de usuário e material histórico excluído. O cabeçalho do cartucho sintético usa um campo de logotipo vazio.
- Comparar licenças, créditos, recursos da marca e o hash da DLL SameBoy com os insumos aprovados. O núcleo e os pacotes têm seus próprios termos. O emblema e o logotipo têm procedência documentada e permissões de redistribuição pendentes. [Créditos](terceiros.md) · [Origem da marca](../design/README.md)
- Gerar a Release em uma pasta limpa. O portátil usa o manifesto de recursos nativos que o Flutter instala em `data/flutter_assets/NativeAssetsManifest.json`. O manifesto duplicado na raiz de builds anteriores era um resíduo de compilação.
- Extrair o ZIP e o Setup e comparar os arquivos com os inventários por nome, tamanho e SHA-256. Conferir versão, AppId, destino por usuário, ícones e atalhos do menu Iniciar e da área de trabalho. O Setup está sem assinatura Authenticode.

A análise por padrões auxilia a identificar material sensível e tem alcance limitado. Os compiladores podem incorporar caminhos de desenvolvimento nos binários. A pasta de build e os intermediários do Inno Setup ficam fora do conjunto de fontes a publicar.

## Resultados de 23/11/2026

| Verificação | Resultado |
|---|---|
| Exportação e privacidade | 162 arquivos comparados à árvore aprovada antes das edições. Na revisão para o primeiro commit, a busca não encontrou o antigo e-mail pessoal, os bytes históricos do logotipo de cartucho, ROMs, saves, chaves ou tokens conhecidos. |
| Fontes e distribuição | Código de emulação, DLL do núcleo, licença MIT, arte e configuração do AppId conferidos. A única mudança de scripts foi retirar a dependência da cópia obsoleta do manifesto de recursos nativos na raiz. |
| Flutter | Análise sem apontamentos, Release x64 compilada e 83 testes aprovados em sequência. Os testes que aceitam um pacote foram executados com o auxiliar extraído do ZIP da beta. |
| Janela nativa | 40 ciclos de entrada e saída da tela cheia aprovados com janela normal e maximizada. |
| Compatibilidade entre versões | O auxiliar do RC2 gerou SRAM, RTC, um slot manual e um rápido com um cartucho MBC3 sintético. O auxiliar da beta retomou a SRAM, leu o RTC avançado e carregou os dois estados com proteção do cartucho. Os hashes dos dois arquivos de estado permaneceram iguais. |
| Inventários | 33 arquivos no portátil e 36 no diretório de instalação, conferidos após extração. O teste de integridade interna do Setup passou. A proteção de empacotamento recusou um arquivo de cartucho adicional. |
| Identidade Windows | Recursos de versão `0.1.1.3`, sete imagens de cada ICO, quatro PNGs de marca e ícone instalado dos atalhos conferidos. A assinatura Authenticode está ausente. |
| Caminhos nos binários | O módulo AOT e os dois auxiliares contêm caminhos de compilação. A inspeção por strings dos arquivos instaláveis não encontrou um caminho pessoal de perfil Windows. |

O ensaio de instalação que altera o registro, cria atalhos e desinstala o aplicativo está reservado a um perfil descartável. Nesta máquina, a conta disponível já tem instalação e dados de uso. A guarda do script foi testada e recusou a execução fora de um perfil de teste.

## Validação e publicação

Os testes de desenvolvimento usam ROMs sintéticas. O proprietário relatou testes manuais da versão anterior em dois PCs Windows. O roteiro RC2 → beta inclui backup, comparação de hashes antes da abertura e retomada de SRAM, RTC, slots manuais, slot rápido e saves das duas posições do Link Cable. [Validar a atualização](validacao-rc2.md)

Após a aprovação da redistribuição da arte, do teste de atualização e da publicação pelo proprietário:

1. Na cópia pública, conferir `git status --short --branch`, `git rev-list --count HEAD`, `git remote -v` e `git tag --list`. Conferir o primeiro commit aprovado e os hashes da distribuição.
2. Criar no GitHub um repositório vazio na conta e com a visibilidade escolhidas. Configurar o endereço desse repositório como `origin` somente na cópia pública e enviar a branch `main`.
3. Criar a tag anotada `v0.1.1-beta.1` no commit aprovado, enviar essa tag e preparar uma GitHub Release marcada como pré-lançamento.
4. Usar o texto das notas e anexar o Setup, o ZIP e `SHA256SUMS.txt` da mesma compilação. Comparar os hashes dos downloads com o registro local.

[Publicar um repositório local no GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github) · [Gerenciar releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
