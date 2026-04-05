# Registro de alterações

## [Unreleased]

### Alterado

- Ao passar o mouse sobre uma célula da grade, agora é exibida uma pré-visualização de janela em miniatura com o ícone do app e a barra de título, em vez de um simples retângulo azul, unificando a aparência com a seleção por arrasto

### Corrigido

- A sobreposição de pré-visualização da grade não era exibida ao passar o mouse sobre a seção Grade nas Configurações
- A sobreposição de pré-visualização da grade não era atualizada em tempo real ao alterar os valores de linhas, colunas ou espaçamento nas Configurações
- Os estados "Mostrar Área de Trabalho" e Mission Control são automaticamente encerrados ao invocar o Tiley pelo atalho global ou ícone da barra de menus
- A janela de sobreposição do Tiley não aparece mais no Mission Control / Exposé

## [4.2.2] - 2026-04-04

### Alterado

- As janelas de sobreposição agora são pré-renderizadas com opacidade zero e mantidas na tela, de modo que exibir a grade de layout requer apenas uma alteração de alfa — reduzindo significativamente a latência percebida
- A janela de configurações agora fecha automaticamente ao clicar em outro aplicativo; o Tiley permanece oculto até que o atalho global seja pressionado novamente

### Corrigido

- Corrigido o clique no ícone do Dock exibindo "Sem janelas" em vez das configurações quando a janela de configurações estava aberta
- Corrigido a janela de configurações desaparecendo permanentemente ao desativar "Mostrar ícone do Dock"
- Corrigido o atalho global que parava de funcionar após a janela de configurações perder o foco para outro aplicativo

## [4.2.1] - 2026-04-04

### Alterado

- Adicionado indicador chevron ao botão de redimensionar para deixar claro que abre um menu suspenso
- Melhorado o timing da ação de redimensionar para que a janela do Tiley desapareça antes de redimensionar a janela alvo, tornando a interação mais intuitiva

## [4.2.0] - 2026-04-04

### Adicionado

- Redimensionar janelas para tamanhos predefinidos (16:9, 16:10, 4:3, 9:16) pelo botão da barra de ferramentas ou menu de contexto; tamanhos que excedem a tela atual são excluídos automaticamente
- Pré-visualização ao vivo ao passar o mouse sobre os itens do menu de redimensionamento: sobreposição em tamanho real na tela de destino e pré-visualização em miniatura na grade (mesmo estilo da pré-visualização de layouts predefinidos)
- Pré-visualização de janela em miniatura (com barra de título e ícone do app) exibida durante a seleção por arrasto na grade

## [4.1.2] - 2026-04-03

### Adicionado

- Emblemas de índice de ordem de seleção exibidos à direita dos itens de janela na barra lateral quando duas ou mais janelas estão selecionadas

### Alterado

- A lista de janelas na barra lateral agora é pré-armazenada em cache em segundo plano por meio de listeners de eventos do workspace (ativação, inicialização e encerramento de apps), aparecendo instantaneamente ao abrir a sobreposição
- Melhorado o comportamento de destaque dos itens agrupados por aplicativo na barra lateral. O cabeçalho do aplicativo só é exibido como selecionado quando todas as suas janelas estão selecionadas, e ao passar o mouse sobre o cabeçalho, tanto o cabeçalho quanto todas as janelas filhas são destacados
- Melhoria no comportamento de saída do modo tela cheia: agora define o atributo AXFullScreen diretamente (com pressionamento de botão como fallback), aguardando até 2 segundos para a conclusão da animação

### Corrigido

- Corrigido o problema de o overlay não abrir quando o aplicativo em primeiro plano não tem janelas. Agora é exibida uma mensagem "Sem janelas" e o arrasto é desativado
- Corrigido o problema de a área de trabalho do Finder ser tratada como uma janela redimensionável. Quando a área de trabalho está em foco, a janela real mais à frente do Finder é selecionada, ou "Sem janelas" é exibido se não houver nenhuma
- Corrigido problema em que a sobreposição não abria quando o aplicativo em primeiro plano não possui janelas (por exemplo, Finder sem janelas abertas, aplicativos apenas de barra de menus); agora utiliza a janela visível mais à frente na tela
- Corrigido problema em que a posição da janela não era aplicada corretamente em monitores não principais para alguns apps (ex.: Notion). Adicionada verificação de posição com lógica de tentativa após o redimensionamento para lidar com apps que revertem a posição de forma assíncrona

## [4.1.1] - 2026-03-31

### Alterado

- O atalho padrão para selecionar a próxima janela foi alterado de Tab para Space; a janela anterior foi alterada de Shift+Tab para Shift+Space
- As janelas deslocadas agora sempre retornam à posição original com animação ao fechar a sobreposição

## [4.1.0] - 2026-03-31

### Adicionado

- Alternância de janelas mantendo teclas modificadoras pressionadas (estilo Cmd+Tab): após abrir a sobreposição, mantenha as teclas modificadoras de alternância pressionadas e pressione a tecla de ativação repetidamente para alternar entre janelas; ao soltar as teclas modificadoras, a janela selecionada é trazida para frente; pressione atalhos locais de layout enquanto mantém as teclas modificadoras para aplicar o layout correspondente
- Seção de agradecimentos de licenças de terceiros nas Configurações (Sparkle, TelemetryDeck)

### Alterado

- Os painéis de Configurações e Permissões agora são janelas independentes em nível normal (não flutuante), para que diálogos de atualização do Sparkle e outras janelas do sistema possam ser exibidos acima
- A barra lateral agora está sempre visível; o botão de mostrar/ocultar foi removido
- O botão de configurações foi movido da barra inferior para a extremidade esquerda da barra de ações da barra lateral
- A visualização de mini tela agora tem cantos arredondados nos quatro lados independentemente do tipo de tela
- A barra de título da janela em miniatura agora exibe o nome do aplicativo junto ao título da janela
- O emblema "Atualização disponível" foi substituído por um ponto vermelho no botão de configurações e uma dica; no painel de configurações, um popover é exibido no botão "Verificar atualizações"

## [4.0.9] - 2026-03-30

### Corrigido

- Redimensionamento de janela falhava e a posição ficava deslocada em certos aplicativos: a posição de rebote quando o redimensionamento inicial era rejeitado ficava na parte inferior da tela (sem espaço para expandir), deixando a janela em uma posição incorreta. Agora o rebote vai para o topo da área visível e a posição é restaurada explicitamente se o redimensionamento continuar falhando
- Janelas deslocadas às vezes não eram restauradas à posição original após selecionar uma janela em segundo plano: a restauração buscava janelas em uma lista que poderia estar desatualizada, causando falhas. Agora as referências de janela são armazenadas diretamente nos dados de rastreamento de deslocamento, e a limpeza é adiada até a conclusão da animação de restauração
- Os botões "Adicionar atalho" / "Adicionar atalho global" só respondiam a cliques perto do centro: o preenchimento e o fundo foram movidos para dentro do rótulo do botão para que toda a área visível seja clicável

## [4.0.8] - 2026-03-30

### Corrigido

- O painel de permissões não é mais exibido sobre outros aplicativos e diálogos do sistema ao solicitar acesso de acessibilidade
- A pré-visualização do papel de parede não era exibida no macOS Tahoe 26.4: adaptação à mudança de estrutura do plist da Store de papéis de parede (`Desktop` → chave `Linked`), papéis de parede de Fotos são carregados do cache BMP do agente de papéis de parede, adicionado o valor de posicionamento `FillScreen` (substituto de `Stretch` no Tahoe), e habilitadas as configurações de modo de exibição para provedores de papéis de parede não do sistema
- Os modos de exibição centralizado e lado a lado renderizavam as imagens muito pequenas quando os metadados DPI da imagem não eram 72 (ex.: capturas de tela Retina a 144 DPI); agora sempre são utilizadas as dimensões reais em pixels

## [4.0.7] - 2026-03-29

### Corrigido

- O modo de exibição lado a lado do papel de parede não era refletido na pré-visualização da minitela (o valor de posicionamento "Tiled" do plist da Store de papéis de parede do macOS não era correspondido corretamente)
- Adicionado registro de depuração para o pipeline de resolução de papel de parede para ajudar a diagnosticar problemas de exibição

## [4.0.6] - 2026-03-29

### Adicionado

- Ao passar o cursor sobre um preset de múltiplos layouts, números de índice de layout são exibidos na grade de mini tela, na pré-visualização em tamanho real e na lista de janelas da barra lateral, permitindo identificar intuitivamente qual layout se aplica a cada janela independentemente da percepção de cores

### Alterado

- Interface da janela de configurações ajustada para corresponder ao visual do macOS Tahoe: botões da barra de ferramentas e de ação unificados com formato de cápsula e fundos de hover/pressão adaptativos ao sistema, cartões de seç��o de configurações com fundo cinza claro sem borda, alternadores redimensionados para o tamanho das Preferências do Sistema, e lista de atalhos reestruturada com uma seção independente "Atalhos para mover ao monitor"

### Corrigido

- Janelas da barra lateral que excedem o número de layouts do preset agora exibem corretamente a cor do último layout em vez da cor de seleção principal

## [4.0.5] - 2026-03-29

### Corrigido

- Janelas deslocadas para exibir a janela de destino selecionada agora retornam corretamente à posição original mesmo ao ciclar rapidamente
- A pré-visualização de redimensionamento de uma única janela estava muito fraca em comparação com as pré-visualizações de layout de múltiplas janelas; agora usa a mesma opacidade

## [4.0.4] - 2026-03-29

### Adicionado

- Ao passar o cursor sobre um preset, a pré-visualização da mini-tela mostra barras de título das janelas (ícone do app, nome do app, título da janela)

### Alterado

- A barra de título da pré-visualização de layout em tamanho real agora exibe o nome do app junto com o título da janela (formato: "Nome do App — Título da Janela")

## [4.0.3] - 2026-03-29

### Adicionado

- Presets com múltiplos layouts agora redimensionam várias janelas mesmo com apenas uma janela selecionada, usando a ordem Z real (janela mais à frente primeiro)
- Quando as janelas selecionadas são menos que as definições de layout, a janela selecionada é sempre tratada como principal e os slots restantes são preenchidos por ordem Z
- Ao passar o cursor sobre um preset com múltiplos layouts, as linhas das janelas afetadas na barra lateral são destacadas com as cores do layout (azul, verde, laranja, roxo)

## [4.0.2] - 2026-03-29

### Alterado

- A pré-visualização de layout em tamanho real agora mostra apenas as pré-visualizações para o número de seleções definidas na predefinição (janelas selecionadas além do número de seleções da predefinição não são mais exibidas)

## [4.0.1] - 2026-03-29

### Alterado

- A paleta de cores de seleção agora cicla entre azul, verde, laranja e roxo (4 cores), de modo que a 5ª seleção corresponde à 1ª
- As predefinições padrão (Metade esquerda/direita/superior/inferior) agora incluem a metade oposta como seleção secundária

## [4.0.0] - 2026-03-29

### Adicionado

- Predefinições de layout com seleção múltipla: defina múltiplas regiões de grade por predefinição para posicionar diferentes janelas em diferentes locais
  - Cada arraste no editor de predefinições adiciona uma nova seleção (1ª, 2ª, 3ª, ...)
  - Cada seleção exibe seu número de índice e um botão de exclusão
  - A sobreposição de seleções é impedida (com feedback visual)
  - Ao aplicar uma predefinição com seleção múltipla, as janelas são atribuídas por ordem de seleção: a primeira janela selecionada recebe a seleção 1, a próxima a seleção 2, etc.
  - As miniaturas e as visualizações em tamanho real exibem todas as seleções com cores indexadas
  - As seleções de grade têm uma margem de 1pt das bordas da tela para melhor visibilidade

### Alterado

- A ordenação de múltiplas janelas agora segue a ordem de seleção em vez da ordem Z da barra lateral
  - A primeira janela selecionada é sempre a principal; janelas adicionadas com Cmd+clique são adicionadas em ordem
  - A seleção por intervalo com Shift+clique mantém a janela âncora como principal
  - Afeta a aplicação de predefinições, trazer para frente (Enter) e exibição de visualização

## [3.4.0] - 2026-03-28

### Adicionado

- Seleção múltipla de janelas na barra lateral com ações em lote
    - Clique no cabeçalho do app para selecionar todas as suas janelas
    - Cmd+clique para adicionar/remover janelas individuais
    - Shift+clique para selecionar um intervalo contínuo de janelas
- Ações em lote na seleção múltipla: trazer para frente (mantendo a ordem Z da barra lateral), redimensionar/mover para a grade, mover para outra tela, fechar/encerrar
- Ao fechar múltiplas janelas selecionadas, apps com todas as janelas selecionadas são encerrados (exceto o Finder)

### Alterado

- Clicar no cabeçalho de um app na barra lateral agora seleciona todas as janelas desse app (anteriormente selecionava apenas a janela da frente)
- Ao selecionar uma janela dentro de um grupo de app, o cabeçalho do aplicativo permanece destacado
- Para apps não-Finder com múltiplas janelas, um botão "Encerrar app" é exibido ao lado do botão "Fechar janela" na barra de ações
- O tooltip "Fechar janela" agora exibe o nome da janela (ex.: Fechar "Documento")

## [3.3.2] - 2026-03-28

### Adicionado

- Os atalhos de teclado para "Selecionar próxima janela", "Selecionar janela anterior", "Trazer para frente" e "Fechar/Sair" agora podem ser configurados na seção de atalhos das preferências
- Novo item de menu de contexto "Fechar outras janelas de [App]" ao clicar com o botão direito em uma janela na barra lateral (exibido apenas quando o app tem várias janelas)

### Alterado

- A seção de configuração de atalhos foi reorganizada em dois grupos: atalhos de ação de janela e atalhos de movimento de monitor
- Os atalhos de movimento de monitor agora são apenas globais; o suporte a atalhos locais e suas opções de configuração foram removidos
- No macOS 26 (Tahoe), os botões da barra de ferramentas, o botão Sair, os botões da barra de ações e o botão de menu suspenso agora usam o efeito interativo do Liquid Glass, seguindo as Human Interface Guidelines
- A cor de fundo da janela agora usa a cor do sistema para melhor compatibilidade com as mudanças de aparência do macOS
- As janelas deslocadas agora retornam à posição original com animação ao confirmar uma seleção, aplicar um layout ou cancelar com Escape

## [3.3.1] - 2026-03-28

### Adicionado

- Ao selecionar uma janela na barra lateral, as janelas sobrepostas são movidas para baixo com uma animação suave para tornar a janela selecionada visível sem alterar o foco
- Uma borda de destaque é exibida ao redor da janela atualmente selecionada na barra lateral

### Corrigido

- Corrigida a ordem de navegação Tab/setas para corresponder à ordem de exibição da barra lateral (agrupada por espaço, tela e aplicativo)
- As janelas deslocadas são restauradas às suas posições originais ao cancelar (Esc) ou fechar o Tiley

## [3.3.0] - 2026-03-27

### Corrigido

- Correção preventiva do uso excessivo de CPU que poderia ocorrer em ambientes com múltiplos monitores
- Correção de um loop de redesenho do ícone da barra de status que poderia causar 100% de uso da CPU quando um selo sobreposto (notificação de atualização ou indicador de depuração) era exibido
- As janelas do Tiley agora flutuam sempre acima das janelas normais para não ficarem ocultas durante a alternância com Tab

## [3.2.9] - 2026-03-27

### Corrigido

- Corrigida a ordem de navegação Tab/setas para corresponder à ordem de exibição da barra lateral (agrupada por espaço, tela e aplicativo)

## [3.2.8] - 2026-03-26

### Corrigido

- Corrigido o problema na barra lateral onde Tab/setas alternavam entre apenas duas janelas em vez de percorrer todas as janelas

## [3.2.7] - 2026-03-26

### Corrigido

- Corrigido um travamento que ocorria ao iniciar o app como item de login (correção incompleta na versão 3.2.6)

## [3.2.6] - 2026-03-26

### Corrigido

- Corrigido um travamento que ocorria ao iniciar o app como item de login

## [3.2.5] - 2026-03-26

### Alterado

- Seções de atalhos e atalhos globais unificadas em uma única seção
- Interface de configuração de atalhos unificada para todos os tipos

### Corrigido

- Corrigido um problema em que a janela principal podia permanecer visível quando o app ia para segundo plano
- Corrigida a borda de destaque que era cortada pelos cantos arredondados e notch em telas integradas (agora é desenhada abaixo da área da barra de menus)

## [3.2.4] - 2026-03-26

### Adicionado

- Adicionados atalhos para mover janelas entre telas (principal, próxima, anterior, escolher no menu, tela específica)

## [3.2.3] - 2026-03-25

### Adicionado

- Adicionados indicadores de seta direcional ao botão e itens de menu "Mover para tela", mostrando visualmente a direção da tela de destino com base na disposição física dos monitores
- Quando a janela selecionada está em outra tela, a sobreposição de grade agora exibe uma seta direcional e um ícone de disposição de telas no centro, orientando o usuário até a localização da janela

### Alterado

- Ajustada a aparência quando uma atualização está disponível

## [3.2.2] - 2026-03-25

### Adicionado

- Ao selecionar uma janela na barra lateral, ela é temporariamente trazida para a frente para facilitar a identificação; a ordem original é restaurada ao mudar para outra janela ou cancelar
- A pré-visualização de redimensionamento agora exibe uma barra de título com o ícone do aplicativo e o título da janela, facilitando a identificação de qual janela está sendo organizada

## [3.2.1] - 2026-03-25

### Corrigido

- Corrigido problema onde a barra lateral não exibia janelas em ambientes com múltiplas telas porque a filtragem de espaços considerava apenas o espaço ativo de uma única tela

## [3.2.0] - 2026-03-25

### Adicionado

- Quando há vários espaços do Mission Control, a barra lateral exibe apenas as janelas do espaço atual
- A sobreposição de grade agora exibe uma pré-visualização da janela em miniatura com botões de semáforo, ícone do app e título da janela na posição atual da janela de destino

### Alterado

- A ocultação da sobreposição está agora mais responsiva ao aplicar layouts ou trazer janelas para frente
- Janelas em modo de tela cheia nativo do macOS agora saem automaticamente da tela cheia antes do redimensionamento

## [3.1.1] - 2026-03-24

### Corrigido

- Corrigido miniaturas de papéis de parede do sistema exibindo em mosaico em vez de preenchimento
- Corrigida imagem incorreta em papéis de parede dinâmicos; adicionado suporte a miniaturas para papéis de parede baseados em provedores Sequoia, Sonoma, Ventura, Monterey e Macintosh
- O texto da barra de menus na visualização da grade agora se adapta ao brilho do papel de parede (preto em fundos claros, branco em escuros, como no macOS)

## [3.1.0] - 2026-03-24

### Alterado

- Substituídos os menus kebab (…) ao passar o mouse na lista de janelas por menus de contexto nativos do macOS (clique direito)
- Adicionados botões de ação (Mover para tela, Fechar/Encerrar, Ocultar outros apps) ao lado do campo de busca da barra lateral
- As miniaturas de grade das predefinições de layout agora refletem a proporção da área utilizável da tela (excluindo a barra de menus e o Dock), adaptando-se à orientação retrato ou paisagem.

### Corrigido

- Corrigido um problema onde o redimensionamento de janelas falhava às vezes ao mover uma janela para outra tela (especialmente para um monitor vertical mais alto), através da introdução de um mecanismo de nova tentativa em movimentações entre telas

### Removido

- Removidos os botões de menu kebab e de fechar ao passar o mouse nas linhas da barra lateral (substituídos por menus de contexto e barra de ações)

## [3.0.1] - 2026-03-23

### Adicionado

- Ao trazer uma janela para frente com Enter ou duplo clique, a janela agora é movida para a tela onde o ponteiro do mouse está localizado, caso seja diferente. A janela é reposicionada para caber na tela e redimensionada apenas se necessário.

### Alterado

- Desempenho de exibição da sobreposição melhorado em ~80% por meio de pooling/reutilização de controladores, carregamento adiado da lista de janelas e renderização prioritária da tela de destino
- Configuração interna de log de depuração renomeada de `useAppleScriptResize` para `enableDebugLog` para melhor refletir sua finalidade

### Corrigido

- Corrigido o redimensionamento de janela falhando silenciosamente na tela principal para alguns aplicativos (ex.: Chrome). O mecanismo de bounce retry usado para telas secundárias agora é aplicado também na tela principal
- Corrigido: clicar no ícone da barra de menus com a sobreposição visível agora fecha a sobreposição (como ESC) em vez de abrir a janela principal

## [3.0.0] - 2026-03-23

### Adicionado

- Integração do SDK TelemetryDeck para análise de uso com respeito à privacidade (abertura da sobreposição, aplicação de layout, aplicação de preset, alteração de configurações)
- As janelas na barra lateral agora são agrupadas por tela e por aplicativo; apps com múltiplas janelas mostram um cabeçalho com as janelas recuadas
- Os cabeçalhos de tela na barra lateral agora têm um menu com ações para "Reunir janelas" e "Mover janelas para" para gerenciar janelas entre telas
- Menu do cabeçalho de aplicativo com "Mover todas as janelas para outra tela", "Ocultar outros" e "Encerrar"
- Menu de apps com janela única com "Mover para outra tela", "Ocultar outros" e "Encerrar"
- Telas vazias (sem janelas) agora são mostradas na barra lateral com seu cabeçalho

### Alterado

- O fundo da grade agora reflete com precisão as configurações de exibição do papel de parede do macOS (preencher, ajustar, esticar, centralizar e mosaico), incluindo dimensionamento correto dos blocos, proporção de pixels físicos para o modo centralizado e cor de preenchimento para áreas de letterbox
- A pré-visualização da grade de layout agora exibe a barra de menus, o Dock e o entalhe, proporcionando uma representação mais fiel da tela real

### Corrigido

- Corrigido um problema onde a janela se movia para uma posição inesperada após o redimensionamento quando já estava na posição de destino. Contorno da deduplicação AX via pré-deslocamento
- Reduzida a cintilação ao redimensionar em telas não principais. O redimensionamento é primeiro tentado no local; o salto para a tela principal só ocorre em caso de falha completa
- Ao saltar para a tela principal, a janela agora é posicionada na borda inferior (quase fora da tela) em vez do canto superior esquerdo, minimizando a cintilação

## [2.2.0] - 2026-03-21

### Alterado

- As células da grade não selecionadas agora são transparentes
- A proporção da grade agora corresponde à área visível da tela (excluindo barra de menus e Dock); se a grade for alta demais, a largura é reduzida proporcionalmente para garantir que pelo menos 4 presets fiquem visíveis
- O fundo da grade de layout agora exibe a imagem de área de trabalho (semitransparente, cantos arredondados)
- As células selecionadas por arrasto agora são semitransparentes, mostrando a imagem de área de trabalho abaixo
- O destaque ao passar o cursor sobre presets na grade agora usa o mesmo estilo da seleção por arrasto

### Adicionado

- A barra lateral da lista de janelas agora é exibida em todas as telas em configurações de múltiplos monitores, não apenas na tela de destino
- O estado da barra lateral (visibilidade, item selecionado, texto de pesquisa) é sincronizado entre todas as janelas de tela
- Log de depuração de redimensionamento opcional (`~/tiley.log`) (Configurações > Depuração)

### Corrigido

- Corrigido um problema onde o posicionamento de janelas usava geometria de tela desatualizada quando o Dock ou a barra de menus eram exibidos/ocultados automaticamente enquanto a sobreposição estava aberta
- Corrigido o redimensionamento de janelas falhando em telas não primárias em configurações de DPI misto; a janela é temporariamente movida para a tela primária para redimensionar e então posicionada no local de destino
- Corrigida a posição não sendo aplicada após redimensionamento quando alguns apps revertem silenciosamente as alterações de posição (contorno de deduplicação AX)
- Quando o tamanho mínimo de janela de um app impede o tamanho solicitado, a posição é recalculada para que a janela permaneça dentro da área visível da tela
- Eliminada a oscilação visível das janelas ao alternar janelas de destino entre telas; as janelas não são mais recriadas na mudança de tela

## [2.1.0] - 2026-03-20

### Adicionado

- Duplo clique em uma janela na barra lateral para trazê-la para o primeiro plano e fechar a grade de layout
- Menu de contexto (botão de reticências) nas linhas de janelas da barra lateral com três ações:
  - "Fechar outras janelas do [App]" — fecha outras janelas do mesmo app (exibido apenas quando o app tem múltiplas janelas)
  - "Encerrar [App]" — encerra o aplicativo
  - "Ocultar janelas exceto [App]" — oculta todos os outros aplicativos (equivalente a Cmd-H), exibe o app selecionado se estava oculto
- Aplicativos ocultos (Cmd-H) agora aparecem na barra lateral como entradas de espaço reservado (apenas nome do app) e são exibidos com 50% de opacidade
- Ao selecionar um app oculto (Enter, duplo clique, redimensionar com grade/layout) ele é automaticamente exibido e a operação é realizada na sua janela principal

## [2.0.3] - 2026-03-19

### Adicionado

- Lembretes suaves de atualização do Sparkle: quando uma verificação em segundo plano encontra uma nova versão, um ponto vermelho aparece no ícone da barra de menus e rótulos "Atualização disponível" são exibidos ao lado do botão de engrenagem e do botão "Verificar atualizações" nas configurações
- Se o ícone da barra de menus estiver oculto, ele é exibido temporariamente com o emblema ao detectar uma atualização e ocultado novamente ao final da sessão

### Alterado

- A janela de configurações é ocultada quando o Sparkle encontra uma atualização (antes apenas no início do download) e restaurada ao cancelar
- O título da janela de configurações agora é localizado em todos os idiomas suportados
- O número da versão foi movido do título das configurações para a seção de atualizações, ao lado do botão "Verificar atualizações"

## [2.0.2] - 2026-03-19

### Adicionado

- Botão de fechar nas linhas da barra lateral de janelas: ao passar o mouse sobre o nome de uma janela, um botão × aparece para fechá-la
- Configuração "Encerrar o app ao fechar a última janela" (Configurações > Janelas): quando ativada (padrão), fechar a última janela de um app encerra o app; quando desativada, apenas a janela é fechada
- O tooltip do botão de fechar mostra o nome da janela; quando a ação encerrará o app, mostra o nome do app
- Atalho de teclado "/" para fechar a janela selecionada (ou encerrar o app se for a última janela e a configuração estiver ativada)

## [2.0.1] - 2026-03-19

### Alterado

- Painel de configurações redesenhado no estilo Tahoe: seções com fundo de vidro (Liquid Glass no macOS 26+), barra de ferramentas compacta com botões voltar/sair e linhas agrupadas estilo iOS com controles em linha

## [2.0.0] - 2026-03-19

### Alterado

- O menu suspenso de seleção de janela alvo foi substituído por um painel lateral com Liquid Glass (macOS Tahoe); inclui campo de busca com suporte completo a IME, navegação por teclas de seta e Tab/Shift+Tab, e Cmd+F para alternar a visibilidade

### Melhorado

- As janelas no painel lateral são listadas em ordem Z (da frente para trás) em vez de agrupadas por aplicativo
- Janelas não padrão (paletas, barras de ferramentas, etc.) foram filtradas da lista de janelas alvo para exibir apenas janelas de documento redimensionáveis

## [1.2.7] - 2026-03-18

### Melhorado

- A janela principal é fechada automaticamente quando o Sparkle começa a baixar uma atualização

### Corrigido

- Eliminadas as emendas visíveis na pré-visualização de restrições de redimensionamento quando as regiões de estouro (vermelho) ou insuficiência (amarelo) são exibidas simultaneamente em ambas as direções

## [1.2.6] - 2026-03-18

### Corrigido

- Ao redimensionar uma janela em segundo plano do mesmo aplicativo via ciclo com Tab, a janela agora é trazida para a frente se ficaria oculta atrás de outras janelas desse aplicativo

## [1.2.5] - 2026-03-18

### Adicionado

- Detecção de restrições de redimensionamento de janelas: detecta automaticamente a capacidade de redimensionamento por eixo através de uma verificação rápida em 3 etapas (não redimensionável → botão de tela cheia → sonda de 1px como fallback)
- A visualização de layout agora mostra regiões vermelhas onde a janela não pode expandir e regiões amarelas onde não pode encolher, fornecendo feedback visual sobre restrições de tamanho antes da aplicação

## [1.2.4] - 2026-03-17

### Melhorado

- Interface de edição de predefinições de layout refinada: botão de exclusão movido para ao lado do botão de confirmação, botões de edição/ação colocados em uma coluna dedicada para evitar sobreposição com os atalhos
- A seleção da grade agora é editável no modo de edição: arraste sobre a grade para atualizar a posição da predefinição com visualização ao vivo e destaque

## [1.2.3] - 2026-03-17

### Melhorado

- Ajuste da interface de edição de predefinições de layout: o botão de exclusão é exibido como sobreposição na visualização da grade, com diálogo de confirmação, fundo opaco ao passar o mouse e estilo de botão uniforme

## [1.2.2] - 2026-03-17

### Alterado

- Remodelada a edição de predefinições de layout para uma experiência de configuração mais intuitiva

## [1.2.1] - 2026-03-17

### Correções

- Corrigido o diálogo "Mover para Aplicativos" exibido incorretamente em vez de "Copiar" ao iniciar a partir de um DMG baixado (Gatekeeper App Translocation impedia o reconhecimento do caminho da imagem de disco)

## [1.2.0] - 2026-03-17

### Adicionado

- Troca de janela alvo: pressione Tab / Shift+Tab enquanto a grade estiver visível para alternar entre as janelas disponíveis
- Menu suspenso de janela alvo: clique na área de informações do alvo para selecionar uma janela em um menu pop-up
- Tab e Shift+Tab agora são teclas reservadas e não podem ser atribuídas como atalhos de layout

## [1.1.8] - 2026-03-16

### Adicionado

- Após copiar de um DMG, oferece ejetar a imagem de disco e mover o arquivo DMG para o Lixo
- Detecção de um DMG do Tiley montado ao iniciar de /Aplicativos (por exemplo, após cópia manual pelo Finder) com opção de ejetar e mover para o Lixo

## [1.1.7] - 2026-03-16

### Alterado

- Formato de distribuição alterado de zip para DMG com atalho para Aplicativos e layout personalizado do Finder (ícones grandes, janela quadrada)

### Correções

- Corrigido "Mover para Aplicativos" falhando com erro de volume somente leitura ao iniciar o app de um zip baixado sem movê-lo primeiro (Gatekeeper App Translocation)
- Exibição do diálogo "Copiar para Aplicativos" em vez de "Mover" quando o app é iniciado de uma imagem de disco (DMG)

## [1.1.6] - 2026-03-16

### Correções

- Corrigido o problema da janela de configurações exigir duas ativações para abrir em configurações com múltiplas telas (ícone da barra de menus, Cmd+, e menu Tiley → Configurações todos afetados)

## [1.1.5] - 2026-03-16

### Adicionado

- Sobreposição multi-tela: a janela de grade de layout agora aparece em todas as telas conectadas simultaneamente
- Mosaico entre telas: arraste a grade ou clique em um preset em uma tela secundária para colocar a janela alvo nessa tela
- A sobreposição de pré-visualização aparece na tela onde a janela do preset é exibida

### Correções

- Corrigido o layout maximizado não preenchendo a tela inteira ao fazer mosaico entre displays de tamanhos diferentes
- Corrigido os atalhos de teclado locais (teclas de seta, teclas de acesso rápido de presets) não funcionando após a segunda ativação da sobreposição
- Corrigido apenas algumas janelas de sobreposição fechando ao clicar em uma janela de app em segundo plano; agora todas as janelas de sobreposição fecham juntas
- Corrigido o destaque de hover/seleção de preset aparecendo em todas as telas; agora só aparece na tela onde o cursor do mouse está

## [1.1.4] - 2026-03-15

### Correções

- Corrigido o botão "Mostrar ícone no Dock" não funcionando: o ícone do Dock não aparecia ao ativar, e ao desativar a janela desaparecia
- Impedido que o app encerre inesperadamente quando todas as janelas são fechadas
- Corrigido o alvo de janela sendo o próprio Tiley ao iniciar com duplo clique; agora direciona corretamente para a janela do app ativo anteriormente
- Corrigido a janela principal aparecendo ao iniciar como item de login: a janela não abre mais no início automático do sistema

## [1.1.3] - 2026-03-15

### Correções

- Corrigido a sobreposição de pré-visualização da grade às vezes permanecendo visível na tela, causando sobreposições duplicadas empilhadas

## [1.1.2] - 2026-03-15

### Adicionado

- Localização: espanhol, alemão, francês, português (Brasil), russo, italiano

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Adicionado

- Suporte ao modo escuro: todos os elementos da interface se adaptam automaticamente à configuração de aparência do sistema

### Alterado

- A exibição de atalhos agora usa símbolos (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) em vez de nomes de teclas em inglês

### Correções

- A janela principal agora se oculta automaticamente quando o Sparkle mostra o diálogo de atualização

## [1.0.1] - 2026-03-15

### Correções

- Adicionada a localização ausente para tooltips dos botões de adicionar atalho ("Adicionar atalho" / "Adicionar atalho global")

## [1.0.0] - 2026-03-14

### Adicionado

- Solicitação para mover o app para /Aplicativos quando iniciado de outro local
- Flag global por atalho: cada atalho dentro de um preset de layout agora pode ser configurado individualmente como global ou local
- Botões de adicionar separados para atalhos regulares e globais, com tooltips popover instantâneos

### Alterado

- Configuração de atalho global movida do nível de preset para o nível de atalho
- Presets existentes com o antigo flag global no nível de preset são migrados automaticamente

## [0.9.0] - 2026-03-14

- Lançamento inicial

### Adicionado

- Sobreposição de grade para mosaico de janelas com tamanho de grade personalizável
- Atalho de teclado global (Shift + Command + Espaço) para ativar a sobreposição
- Arrastar sobre células da grade para definir a região da janela alvo
- Presets de layout para salvar e restaurar arranjos de janelas
- Suporte a múltiplos displays
- Opção de iniciar ao fazer login
- Localização: inglês, japonês, coreano, chinês simplificado, chinês tradicional
