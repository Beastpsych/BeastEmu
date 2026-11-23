# Conferência da beta Windows

Esta é a primeira árvore preparada para publicação do BeastEmu. Ela foi exportada dos arquivos rastreados da versão aprovada e recebeu um histórico Git independente. O nome de versão é `0.1.1-beta.1+3`, com recurso numérico Windows `0.1.1.3`. Os nomes e hashes dos dois pacotes estão nas [notas de lançamento](release-beta.md).

## Escopo da conferência

- Conferir cada arquivo da exportação por hash Git e revisar as diferenças de versão, documentação e empacotamento antes do primeiro commit.
- Inspecionar nomes, conteúdo e metadados em busca de jogos, BIOS, saves, perfis, credenciais, caminhos de usuário e material histórico excluído. O cabeçalho do cartucho sintético usa um campo de logotipo vazio.
- Comparar licenças, créditos, recursos da marca e o hash da DLL SameBoy com os insumos aprovados. O núcleo e os pacotes têm seus próprios termos. A política aprovada permite redistribuir as versões oficiais inalteradas com a identidade original e os avisos. [Política da marca](../MARCA.md) [Créditos](terceiros.md) · [Origem da marca](../design/README.md)
- Gerar a Release em uma pasta limpa. O portátil usa o manifesto de recursos nativos que o Flutter instala em `data/flutter_assets/NativeAssetsManifest.json`. O manifesto duplicado na raiz de builds anteriores era um resíduo de compilação.
- Extrair o ZIP e o Setup e comparar os arquivos com os inventários por nome, tamanho e SHA-256. Conferir versão, AppId, destino por usuário, ícones e atalhos do menu Iniciar e da área de trabalho. O Setup está sem assinatura Authenticode.

A análise por padrões auxilia a identificar material sensível e tem alcance limitado. Os compiladores podem incorporar caminhos de desenvolvimento nos binários. A pasta de build e os intermediários do Inno Setup ficam fora do conjunto de fontes a publicar.

## Conferência do candidato inicial em 23/11/2026

| Verificação | Resultado |
|---|---|
| Exportação e privacidade | 162 arquivos comparados à árvore aprovada antes das edições. Na revisão para o primeiro commit, a busca não encontrou o antigo e-mail pessoal, os bytes históricos do logotipo de cartucho, ROMs, saves, chaves ou tokens conhecidos. |
| Fontes e distribuição | Código de emulação, DLL do núcleo, licença MIT, arte e configuração do AppId conferidos. Na exportação inicial, a mudança de scripts foi retirar a dependência da cópia obsoleta do manifesto de recursos nativos na raiz. |
| Flutter | Análise sem apontamentos, Release x64 compilada e 83 testes aprovados em sequência. Os testes que aceitam um pacote foram executados com o auxiliar extraído do ZIP da beta. |
| Janela nativa | 40 ciclos de entrada e saída da tela cheia aprovados com janela normal e maximizada. |
| Compatibilidade entre versões | O auxiliar do RC2 gerou SRAM, RTC, um slot manual e um rápido com um cartucho MBC3 sintético. O auxiliar da beta retomou a SRAM, leu o RTC avançado e carregou os dois estados com proteção do cartucho. Os hashes dos dois arquivos de estado permaneceram iguais. |
| Inventários | 33 arquivos no portátil e 36 no diretório de instalação, conferidos após extração. O teste de integridade interna do Setup passou. A proteção de empacotamento recusou um arquivo de cartucho adicional. |
| Identidade Windows | Recursos de versão `0.1.1.3`, sete imagens de cada ICO, quatro PNGs de marca e ícone instalado dos atalhos conferidos. A assinatura Authenticode está ausente. |
| Caminhos nos binários | O módulo AOT e os dois auxiliares contêm caminhos de compilação. A inspeção por strings dos arquivos instaláveis não encontrou um caminho pessoal de perfil Windows. |

O ensaio automatizado que altera o registro, cria atalhos e desinstala o aplicativo requer um perfil descartável. Nesta máquina, a conta disponível já tem instalação e dados de uso. A guarda do script foi testada e recusou a execução fora de um perfil de teste.

## Reempacotamento com a política da marca

O ZIP final contém 34 arquivos e o diretório instalado contém 37. Os dois pacotes foram extraídos e comparados aos inventários por nome, tamanho e SHA-256. A licença MIT e a política da marca coincidem com os arquivos do repositório. Em relação aos inventários do candidato anterior, as únicas diferenças são `MARCA.md`, `LEIA-ME.md`, `licenses/CREDITOS.md` e, no instalador, `INSTALACAO.md`. Todos os binários, imagens e avisos de licença anteriores conservam seus hashes. O Setup passou no teste de integridade interna. Em uma cópia de teste, o empacotador recusou uma política com conteúdo divergente. As notas identificam os arquivos finais pelos novos hashes.

Com o portátil final extraído, a suíte Flutter passou nos 83 testes em sequência e a análise estática terminou sem apontamentos. Na árvore pública foram verificados 163 arquivos rastreados, incluindo as 27 imagens e ícones enumerados pela política. A busca por padrões e pelos identificadores históricos conhecidos não encontrou credenciais, perfis pessoais, saves ou ROMs comerciais. Os dados de compilação locais permanecem fora do Git.

## Validação e publicação

Os testes de desenvolvimento usam ROMs sintéticas. O proprietário relatou testes manuais da versão anterior em dois PCs Windows. O roteiro RC2 → beta inclui backup, comparação de hashes antes da abertura e retomada de SRAM, RTC, slots manuais, slot rápido e saves das duas posições do Link Cable. [Validar a atualização](validacao-rc2.md)

O proprietário confirmou o ciclo externo de instalação, atualização, desinstalação e reinstalação. Essa confirmação se refere ao candidato avaliado antes do reempacotamento da documentação. A troca de Pokémon em cartuchos reais continua sem validação documentada.

### Publicação futura pelo responsável

Execute os passos abaixo somente após a decisão de publicar.

1. Na cópia pública, conferir `git status --short --branch`, `git rev-list --count HEAD`, `git remote -v` e `git tag --list`. Confirmar árvore limpa, dois commits, raiz `8c942542baee9bf112253abe6a25b814b94d7e29`, ausência de tags e remotos e correspondência do HEAD com o commit aprovado. Comparar os hashes da distribuição com as notas.
2. Criar no GitHub um repositório público vazio na conta escolhida, deixando README, licença e .gitignore desmarcados. Na cópia pública, usar `git remote add origin URL-DO-REPOSITORIO`, conferir `git remote -v` e usar `git push -u origin main`.
3. Criar a tag no commit conferido com `git tag -a v0.1.1-beta.1 HEAD -m "BeastEmu v0.1.1-beta.1"`. Enviar somente essa tag com `git push origin refs/tags/v0.1.1-beta.1`.
4. Em **Releases → Draft a new release**, selecionar a tag existente e usar o título **BeastEmu v0.1.1-beta.1 para Windows x64**. Copiar as notas, ajustando os links relativos para apontar aos arquivos na tag. Anexar apenas o Setup, o ZIP e `SHA256SUMS.txt` da mesma compilação. Marcar **Set as a pre-release**, revisar o rascunho e escolher **Publish release**. Baixar os dois pacotes publicados e comparar seus SHA-256 com os das notas.

[Publicar um repositório local no GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github) · [Gerenciar releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
