# BeastEmu · recursos de marca

![Logotipo BeastEmu](../assets/brand/logo-horizontal.png)

O emblema dracônico e o logotipo BeastEmu foram criados por geração de imagens no ChatGPT, sob a direção visual aprovada pelo responsável pelo projeto. As referências foram adaptadas para a interface, os ícones do Windows e o instalador. A [política da marca](../MARCA.md) identifica os arquivos e autoriza o estudo, a compilação e a redistribuição de versões oficiais inalteradas com os avisos. O código autoral permanece sob MIT.

As duas referências aprovadas estão em `references/`, com a extensão dupla `.png.png` fornecida. O emblema frontal detalhado e o perfil de dragão da prancha são duas aplicações distintas da marca. A prancha original mede 1536 × 1024 e o emblema original, 1254 × 1254.

| Recurso | Dimensões em pixels | Aplicação |
|---|---|---|
| `assets/brand/emblem.png` | 384 × 384 | Emblema original reduzido, com transparência, na tela inicial ampla e em Configurações → Sobre o BeastEmu. |
| `assets/brand/logo-horizontal.png` | 666 × 128 | Perfil e lettering recortados da faixa inferior da prancha, para barra lateral e cabeçalho estreito. |
| `assets/brand/logo-compact.png` | 276 × 190 | Composição empilhada do mesmo perfil e lettering, para o estado vazio da biblioteca. |
| `assets/brand/symbol.png` | 184 × 169 | Perfil transparente para cabeçalhos estreitos e capas padrão. |
| `design/exports/icons/app-*.png` e `setup-*.png` | 16, 24, 32, 48, 64, 128 e 256, quadrados | Exportações individuais de cada ICO. |
| `windows/runner/resources/app_icon.ico` | Sete resoluções | Executável, janela, barra de tarefas e atalhos do aplicativo. |
| `windows/runner/resources/setup_icon.ico` | Sete resoluções | Executável do instalador Inno Setup. |

O lettering metálico é a imagem aprovada, sem instalação de fonte. A composição horizontal aproxima a fera do nome. A versão compacta empilha os dois elementos. Ambas dispensam o separador e a legenda de consoles do rodapé da prancha. Um recorte por luminosidade remove o fundo escuro e suaviza as bordas. Nos ICOs, a partir de 48 px aparecem o azulejo com borda vermelha ou a caixa do instalador. Até 32 px ambos usam o perfil prateado ampliado, sem moldura e sem texto. O espaço transparente preserva as proporções.

Na interface, o vermelho principal é `#C1121F`, o painel carvão é `#17171B` e o texto prateado da assinatura usa `#D9D9DE`. Os degradês e reflexos das imagens mantêm as cores das referências. Durante o jogo, a marca fica no ícone nativo da janela, fora da imagem dos cartuchos.

Para reproduzir os PNGs e ICOs, execute `./design/export-brand.ps1` em PowerShell 7 no Windows. O script usa GDI+ e lê somente os dois originais. O Flutter incorpora apenas os quatro PNGs listados em `pubspec.yaml`. O compilador de recursos do Windows e o Inno Setup incorporam os ICOs nos respectivos executáveis.

## Prévias de validação

O aplicativo foi renderizado pelo runner Flutter Windows em uma janela de avaliação com perfil temporário. As dimensões do conteúdo são 1264 × 681 e 504 × 681. O recorte do Explorer mostra o executável extraído do ZIP final. Na barra de tarefas desta máquina, o perfil aparece a 24 px. Em fundo claro, a crina prateada tem menos contraste que no painel carvão. A revisão visual em outros níveis de escala e na atualização de um atalho já fixado continua no checklist do outro computador.

[Início](previews/inicio.png) · [Janela estreita](previews/janela-estreita.png) · [Tela Sobre](previews/sobre.png) · [Explorer](previews/explorer.png) · [Barra de tarefas](previews/taskbar.png)
