# Registro de alterações

## [Unreleased]

### Melhorado

- A janela principal é fechada automaticamente quando o Sparkle começa a baixar uma atualização

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
