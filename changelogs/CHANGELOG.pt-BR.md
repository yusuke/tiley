# Registro de alterações

## [Unreleased]

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
