# Registro de alterações

## [Unreleased]

### Corrigido

- Ao editar uma predefinição de layout que já tinha slots com apps atribuídos, o número exibido dentro do retângulo sendo arrastado (e sua cor) era um a mais: os slots atribuídos eram contados mesmo mostrando um ícone em vez de um número. As pré-visualizações de arrasto e de hover agora usam a mesma numeração dos retângulos confirmados.
- O Tiley executava uma varredura completa de Acessibilidade em todas as janelas abertas (além de uma consulta à lista de janelas do WindowServer) a cada troca de foco ou de janela em qualquer aplicativo — mesmo quando o recurso de agrupamento de janelas não estava sendo usado. A atualização dos badges agora retorna imediatamente quando não há grupos vinculados nem candidatos a grupo pendentes, e os eventos de mudança de foco são agrupados, de modo que uma única troca de janela (que dispara tanto a notificação de Acessibilidade de janela em foco quanto a de janela principal) causa no máximo uma atualização em vez de duas. Isso elimina a carga constante de CPU/IPC ao alternar entre aplicativos normalmente.
- A sobreposição do Tiley relia do disco os metadados do papel de parede e a configuração do Dock a cada passagem de renderização do SwiftUI: a plist do Store de papéis de parede era reanalisada até quatro vezes por passagem (e o arquivo do papel de parede reaberto para ler suas dimensões em pixels), e quando uma borda do Dock estava visível, a plist do Dock e todos os ícones de seus aplicativos também eram recarregados a cada vez — E/S de disco síncrona na thread principal na frequência do movimento do mouse. As informações de exibição do papel de parede agora são armazenadas em cache por tela e invalidadas quando o papel de parede ou a configuração de telas muda, e o conteúdo do Dock é lido apenas uma vez a cada abertura da janela.
- Arrastar uma seleção pela grade reconstruía a sobreposição de pré-visualização da tela a cada evento do mouse: cada movimento recriava toda a hosting view SwiftUI da sobreposição mesmo quando as células destacadas não haviam mudado. Agora a pré-visualização só é atualizada quando a seleção realmente passa para outra célula, e a sobreposição reutiliza uma única hosting view em vez de reconstruí-la — eliminando o pico de CPU durante o arraste (a mesma reutilização se aplica às pré-visualizações de hover de presets, de redimensionamento e da grade de ajustes).
- Mover ou redimensionar um grupo de janelas vinculado fazia polling a 120 Hz com chamadas síncronas de Acessibilidade, incluindo até três idas e voltas de verificação e correção por janela seguidora em cada tick ao redimensionar, e procurava janelas com varreduras lineares centenas de vezes por segundo. O polling agora roda a 60 Hz com uma única passada de verificação por tick (a correção ao soltar continua fixando as posições finais), as buscas de janelas usam um índice O(1), e os aplicativos seguidores recebem um tempo limite curto de mensagens de Acessibilidade durante o arraste, de modo que um aplicativo ocupado não consegue mais travar o Tiley no meio do arraste.
- Com grupos vinculados ou badges de agrupamento ativos, as operações de grupo reliam as posições das janelas com muito mais frequência do que o necessário: formar, dissolver ou revalidar um grupo varria a posição de todas as janelas abertas por meio de leituras síncronas de Acessibilidade várias vezes por evento (um único clique em uma janela pareada podia disparar de seis a oito varreduras completas), e as atualizações de badges varriam todas as janelas a cada mudança de foco. Todos esses caminhos agora leem apenas as janelas realmente envolvidas (membros do grupo e candidatas a badge), de modo que o tráfego de Acessibilidade por evento não cresce mais com o número total de janelas abertas.
- Aplicar um layout não bloqueia mais o aplicativo. A sequência de movimentação de janelas (que espera deliberadamente entre as etapas de Acessibilidade para vencer aplicativos que revertem posições) era executada em série na thread principal — um preset de quatro janelas bloqueava o Tiley por 200 ms ou mais, além de cerca de 100 ms por aplicativo na sequência de trazer para a frente. As movimentações agora rodam em threads de segundo plano com janelas independentes movidas em paralelo, as esperas da sequência de trazer para a frente não bloqueiam mais a thread principal, e aplicações repetidas rápidas são enfileiradas mantendo a ordem. O timing das etapas de Acessibilidade por janela permanece inalterado.
- A consulta janela→Space emitia uma requisição ao WindowServer por janela a cada atualização da lista de janelas (ou seja, após cada troca de aplicativo). As atribuições de Space agora têm um cache de curta duração (no máximo cinco segundos, descartado nas mudanças de Space), e o monitor de grupos divididos entre Spaces — que ignora o cache de propósito — verifica a cada dois segundos em vez de a cada segundo.
- As linhas da barra lateral resolviam seus parceiros de vínculo de grupo com varreduras lineares e consultas de bundle por linha a cada passagem de renderização, e um defeito de cache fazia a consulta de nome de aplicativo usada pelo campo de busca reler o Info.plist do disco a cada uso para a maioria dos aplicativos (o resultado negativo nunca era armazenado). A resolução de parceiros agora termina imediatamente para janelas sem vínculos e usa consultas indexadas, e ambos os caches de nomes armazenam também resultados negativos.
- O primeiro pressionamento de troca de janela após abrir a sobreposição, e a resolução do alvo em alguns caminhos, ainda executavam uma enumeração completa e síncrona de Acessibilidade de todas as janelas abertas na thread principal — uma pausa de mais de 100 ms com muitas janelas. Ambos agora reutilizam a lista já alinhada com a ordem real das janelas na abertura, recorrendo a uma captura síncrona apenas quando não existe lista alguma (primeira inicialização); a atualização autoritativa em segundo plano reconcilia instantes depois.
- Em configurações com várias telas, cada tela que não hospeda o ícone de status da barra de menus reamostrava seu papel de parede a cada passagem de renderização para escolher a cor do texto da barra de menus em miniatura — rasterizando a imagem e calculando um histograma de cerca de 50.000 pixels por passagem. A cor amostrada agora é armazenada em cache por tela e recalculada apenas quando o papel de parede ou a configuração de telas muda.
- Com vínculos satélite registrados, cada evento de movimento ou redimensionamento de qualquer janela consultava o Launch Services uma vez por bundle de app registrado antes mesmo de verificar se a janela movida fazia parte de um par — repetido muitas vezes por segundo durante qualquer arraste de janela. A verificação de relevância agora roda primeiro com comparações de ID baratas, e a consulta ao bundle só acontece em eventos que realmente envolvem um par vinculado.
- Os botões suspensos da barra de ações (mover para tela / redimensionar) forçavam um redesenho completo do AppKit a cada passagem de atualização do SwiftUI — na frequência de hover ou tecla — e cada redesenho recolorizava suas imagens de SF Symbol copiando e re-renderizando os bitmaps. Agora os botões só redesenham quando uma entrada realmente usada pelo desenho muda, e as imagens de símbolos coloridas são armazenadas em cache por símbolo, tamanho, tonalidade e aparência (trocas de tema continuam renderizando cores novas).
- Os painéis de badges de agrupamento eram totalmente re-renderizados a cada atualização de badges — cada atualização reconstruía a árvore de views SwiftUI de cada badge e redefinia a posição do painel mesmo quando nada havia mudado. Os badges agora se comparam com o estado anterior e pulam a re-renderização quando posição, estado e flags de hover estão todos inalterados.
- Ações de janela em massa (mover todas as janelas de um app ou de uma tela inteira para outro monitor, fechar várias janelas, ocultar apps) agendavam uma atualização completa da lista de janelas por janela afetada. Agora elas se aglutinam em uma única atualização adiada, de modo que o custo pós-ação permanece constante independentemente de quantas janelas estavam envolvidas.
- Cada inicialização a partir da pasta Aplicativos executava de forma síncrona o `hdiutil info` (que pode levar centenas de milissegundos) na thread principal para verificar se uma imagem de disco do Tiley ainda estava montada — e, ao encontrá-la, executava um segundo `hdiutil` apenas para resolver um caminho que a primeira consulta já havia retornado. A detecção agora roda em segundo plano e só volta à thread principal quando uma imagem montada é realmente encontrada; a segunda consulta redundante foi eliminada, e a limpeza de ejetar/lixeira após o relançamento também não bloqueia mais a inicialização.
- A janela de ajustes resolvia novamente as impressões digitais de identidade das telas conectadas e reconstruía o conjunto de presets padrão a cada passagem de renderização — a cada tick ao arrastar os controles deslizantes da grade. Ambos agora são memoizados e recalculados apenas quando a configuração de telas ou o tamanho da grade realmente muda.
- Editar um preset (renomear, atribuir apps, editar retângulos) cancelava e registrava novamente todos os atalhos globais de presets a cada mudança, e reordenar também. Agora os atalhos só são registrados novamente quando uma edição realmente toca os atalhos de um preset; reordenações e presets recém-criados pulam isso completamente.
- Com o log de depuração ativado, cada linha abria, anexava e fechava o arquivo de log — tornando os caminhos de alta frequência limitados por E/S exatamente enquanto eram medidos. O identificador do arquivo agora é aberto uma vez e reutilizado.
- O botão de redimensionar da barra lateral lia a posição da janela por meio de uma chamada síncrona de Acessibilidade ao app de destino — e buscava seu ícone — a cada passagem de renderização do SwiftUI (cada hover, tecla ou hover em um preset, uma vez por tela). Um app de destino ocupado podia travar a sobreposição a cada passagem. Agora a posição é lida uma única vez quando o menu de redimensionar é realmente aberto, o ícone vem do cache por janela e a lista de presets de tamanho que cabem na tela é armazenada em cache por tamanho de tela.
- Cada início de arrasto na grade — e cada saída e retorno do ponteiro — destruía a janela de pré-visualização de layout em tela cheia e criava outra (um NSWindow novo com hosting view e um backing store do tamanho da tela); além disso, ao arrastar fora da grade, cada evento do mouse reescrevia o estado do preset selecionado e re-renderizava a sobreposição em todas as telas na frequência dos eventos do mouse. A janela de pré-visualização agora permanece viva enquanto a interface do Tiley está aberta e só é liberada ao fechar a sobreposição ou quando a configuração de telas muda; o arrasto fora da grade informa a transição uma única vez, e gravações de seleção de preset sem alteração são ignoradas.
- A camada de modelo consultava ícones de apps e identificadores de bundle via Launch Services a cada passagem de renderização do SwiftUI e a cada mudança de célula (pré-visualização de janelas da mini área de trabalho, pré-visualização de layout ao vivo e hover em presets, que percorria duas vezes todas as janelas abertas), e como cada consulta retornava um novo objeto de ícone, as views de pré-visualização nunca podiam ser reconhecidas como inalteradas. Essas consultas agora passam por um cache por processo (descartado quando o processo encerra), de modo que entradas idênticas produzem valores idênticos e as views pulam a re-renderização; a janela de pré-visualização também não reemite o pedido de trazer para frente a cada mudança de célula.
- O Tiley observa todas as janelas quanto a movimentos e redimensionamentos para oferecer os selos de "formar grupo", e a cada evento relia a posição e o tamanho da janela por meio de duas chamadas síncronas de Acessibilidade ao app — e então descartava o resultado. Arrastar qualquer janela em qualquer app custava, portanto, duas idas e voltas por evento ao app arrastado. Essa leitura foi removida; as notificações de mudança de janela em foco e de janela principal (ambas disparadas por um único clique) agora executam o vínculo de elevação uma vez em vez de duas, e as notificações no nível do app são registradas uma vez por app em vez de uma por janela.
- Cada troca de aplicativo (Cmd-Tab ou clique em outro app) executava uma consulta da lista de janelas ao WindowServer mais uma reordenação completa da lista de janelas em cache do Tiley cujo resultado nunca era exibido (a sobreposição realinha o cache assim que abre), e 200 ms depois disparava uma consulta síncrona de Acessibilidade ao app recém-ativado mesmo sem nenhum grupo de janelas — de modo que um app sem resposta podia travar o Tiley pelos seis segundos do tempo limite padrão. O realinhamento redundante foi removido, a verificação de grupos agora ocorre antes de qualquer chamada de Acessibilidade, o sinalizador de permissão de acessibilidade só é gravado quando realmente muda, e o Tiley agora define um tempo limite de Acessibilidade de um segundo para todo o processo, para que um app travado não possa mais bloqueá-lo por segundos.
- Ao soltar uma janela após movê-la ou redimensioná-la — em qualquer app —, o Tiley relia a posição e o tamanho de todas as janelas abertas por meio de chamadas síncronas de Acessibilidade (duas por janela, na thread principal) para verificar se a janela movida agora toca outra. Com 30–40 janelas, eram 60–80 idas e voltas por arrasto, e a mesma passagem podia executar duas vezes por gesto. A detecção agora lê apenas as janelas movidas mais as janelas na tela cujos limites atuais estão próximos delas (obtidas com uma única consulta da lista de janelas), e o temporizador de acomodação é rearmado em vez de recriado a cada evento de movimento.
- Após aplicar um layout, as janelas que o Tiley acabara de posicionar às vezes eram tratadas como se o usuário as tivesse arrastado manualmente: as notificações de movimento de Acessibilidade enviadas com atraso pelos apps chegavam depois que a supressão dos movimentos do próprio Tiley terminava, o que executava a verificação de adjacência de movimento manual em todas as janelas na tela e exibia selos de "formar grupo" entre uma janela posicionada e uma janela não relacionada atrás dela cuja borda coincidia por acaso — assim uma borda recém-agrupada podia mostrar um selo de vínculo extra. O Tiley agora registra os quadros das janelas que posiciona para reconhecer essas notificações tardias como ecos de seus próprios movimentos.
- Vários pequenos trabalhos por passagem de renderização da janela de sobreposição eram repetidos a cada hover, tecla ou arrasto, uma vez por tela: o nome de cada tela era consultado novamente ao driver de vídeo para os cabeçalhos da barra lateral, os metadados do papel de parede e a tela em pré-visualização eram resolvidos de três a quatro vezes, o preset em edição e o preset sob o cursor eram procurados até nove vezes cada para alimentar a grade, cada miniatura de preset varria todos os seus retângulos a cada célula e, assim que existia algum grupo de janelas ou par satélite, cada linha da barra lateral reconstruía suas próprias tabelas de consulta para os selos de vínculo. Agora os nomes das telas são armazenados em cache, as entradas de tela / papel de parede / preset são resolvidas uma vez por passagem, a barra lateral monta suas tabelas de vínculo uma única vez e as compartilha entre as linhas, e as miniaturas de preset comparam suas entradas e pulam o redesenho quando nada mudou.
- A sobreposição podia permanecer na tela após clicar na janela de outro app. No macOS 14 e posteriores, o sistema pode se recusar a tornar o Tiley o app ativo quando o atalho é pressionado logo após interagir com outro app (por exemplo, imediatamente após clicar em outra janela para fechar a sobreposição anterior); a sobreposição ficava visível sem que o Tiley estivesse ativo, então clicar em outro lugar nunca produzia a desativação que a oculta. Agora o Tiley verifica a ativação logo após mostrar a sobreposição e tenta novamente e — caso ainda seja recusada — um clique fora das janelas do Tiley oculta a sobreposição diretamente.
- Cada captura da lista de janelas (executada em segundo plano após cada troca de app e a cada abertura da sobreposição) fazia três ou quatro idas e voltas de Acessibilidade separadas por janela — subfunção, posição, tamanho e depois o título — e, por janela, obtinha novamente a lista de apps em execução, criava um novo elemento de aplicativo de Acessibilidade e reenumerava as telas. Também copiava duas vezes a lista de janelas na tela apenas para verificar Show Desktop / Mission Control. Agora os atributos de cada janela são obtidos em uma única ida e volta, a lista de apps, os elementos de aplicativo e a lista de telas são coletados uma vez por captura, e as duas verificações compartilham uma única cópia da lista de janelas.
- As operações de grupos de janelas repetiam o mesmo trabalho várias vezes por ação do usuário: desfazer um grupo disparava uma revalidação completa de todos os outros grupos (relendo o quadro de cada membro via Acessibilidade) mais uma atualização de selos, e o revínculo de satélites ou uma divisão de Space desfazia dois ou mais grupos em sequência — assim um único clique em uma janela pareada podia executar quatro a cinco atualizações de selos e sete a oito consultas da lista de janelas; vincular, desvincular, expiração de candidatos e janelas destruídas executavam cada um sua própria atualização imediata; aplicar um layout desvinculava as adjacências de borda de tela uma a uma com uma atualização completa a cada vez; e um único clique chegava até três vezes ao manipulador de elevação do grupo. Agora as dissoluções múltiplas revalidam uma vez no final, as atualizações finais são agrupadas no próximo ciclo do run loop, a revalidação repassa à atualização os quadros já lidos, a desvinculação pré-layout divide o grupo uma única vez sem atualização intermediária, e despachos de elevação repetidos para a mesma janela em 100 ms são descartados.
- Um único contador de versão comandava todas as visualizações da sobreposição que dependem da lista de janelas, e ele era incrementado tanto por mudanças de seleção quanto de lista: uma única abertura da sobreposição o avançava quatro a cinco vezes, cada clique na barra lateral duas vezes, e cada incremento também apagava o cache por app da barra lateral (ícone, ID do bundle, nome original), de modo que a renderização seguinte resolvia de novo o app de cada linha via Launch Services e relia seu Info.plist. A atualização em segundo plano que chega após a abertura também republicava a lista mesmo quando idêntica à já exibida. Agora as mudanças de seleção avançam um contador separado observado apenas pelas visualizações dependentes da seleção, o cache por app é invalidado somente quando o conjunto de apps realmente muda, e uma atualização que produz a mesma lista não a republica mais.
- Várias ações de grupo ainda bloqueavam a thread principal com a sequência síncrona de movimentação de janelas (que espera deliberadamente entre os passos de Acessibilidade): preencher um grupo até a borda da tela esperava pelo menos 50 ms por membro, trocar duas janelas e igualar suas dimensões idem, e cada troca de satélite restaurava a posição da âncora — mais até quatro verificações de deriva — da mesma forma, de modo que um clique em um selo ou uma troca de satélite podia congelar o Tiley por 100–250 ms (até um segundo quando um app rejeita o quadro). Confirmar uma única janela com Enter também bombeava o run loop por 50 ms, e confirmar em um app oculto mantinha a sobreposição na tela durante a espera de 150 ms para exibi-lo. Agora esses movimentos são executados em threads de segundo plano com o estado do grupo atualizado quando terminam (e a supressão do vínculo de grupo mantida até lá em vez de 0,1 s fixos), a confirmação de janela única suspende em vez de bombear, e as janelas do Tiley saem da tela antes da espera de exibição.
- Depois de igualar as alturas (ou larguras) de duas janelas vinculadas, arrastar uma delas podia deixar o par desalinhado quando o app relatava o arrasto como movimento e redimensionamento simultâneos (como o macOS faz ao desfazer o mosaico de uma janela que preenchia a tela): a parceira é solicitada a seguir a translação perpendicular, mas alguns apps a ignoram, e o encaixe ao soltar que deveria realinhar as bordas compartilhadas decidia se elas eram "compartilhadas" a partir de caches que a resolução anterior de lacunas/sobreposições tinha acabado de sobrescrever com o quadro real da parceira — concluindo que não eram e deixando o desajuste. Agora as bordas compartilhadas são registradas no início do arrasto e o encaixe ao soltar usa esse registro.
- Passar o ponteiro sobre uma linha da barra lateral de janelas da sobreposição reavaliava todo o corpo da sobreposição naquela tela — a composição da tela, a grade com suas janelas em miniatura, cada linha de preset e a barra de dicas — porque o estado de hover das linhas ficava na visualização de nível superior. A lista de linhas da barra lateral agora é uma visualização própria que possui esse estado de hover, então mover o ponteiro pela lista redesenha apenas as linhas.
- Mais dois custos por renderização na sobreposição: mover o ponteiro pela grade recomparava cada célula base (até 144, cada uma varrendo as seleções) porque a célula sob o cursor era uma entrada de toda a grade de células, e cada reavaliação do corpo da sobreposição — um hover em um preset, uma mudança de seleção, uma tecla — reconstruía do zero a lista de linhas da barra lateral e suas tabelas de consulta de vínculos mesmo sem mudança nas entradas. As células base agora são uma visualização separada comparada por valor com o preenchimento de hover desenhado como uma única sobreposição, e as linhas da barra lateral e as tabelas de consulta são memorizadas conforme a lista de janelas, o texto de busca, os Spaces, a configuração de telas e o estado dos grupos.
- O caminho do atalho carregava vários pequenos custos a cada pressionamento ou fechamento: as compilações de lançamento perguntavam ao Launch Services a cada pressionamento se uma compilação de depuração estava em execução (o sinalizador já é mantido pelos observadores de inicialização/término), o manipulador passava por uma tarefa antes de abrir a sobreposição, cada fechamento desmontava e registrava novamente o atalho principal inalterado e reconstruía o resolvedor de impressões digitais de telas (que lê fabricante/modelo/série de cada tela), e a etapa pós-abertura copiava a lista de janelas na tela na thread principal para detectar Show Desktop / Mission Control e depois lia a posição da janela alvo por uma chamada síncrona de Acessibilidade que a atualização autoritativa tornava redundante. Agora o pressionamento abre a sobreposição diretamente, o atalho principal permanece registrado entre fechamentos, o resolvedor é memorizado conforme a configuração de telas, a verificação de Exposé roda fora da thread principal e a leitura redundante de Acessibilidade foi removida.
- Percorrer a janela alvo (Tab, setas ou um clique na barra lateral) alocava uma nova janela de pré-visualização em tela cheia a cada passo mesmo quando o alvo permanecia na mesma tela, forçava dois commits síncronos do Core Animation por passo e lia a posição de cada janela que a cobria duas vezes via Acessibilidade. Agora a janela de pré-visualização é reutilizada sempre que a tela coincide, a animação de deslocamento simplesmente começa um quadro depois em vez de forçar um commit, e cada janela que cobre é lida uma única vez.
- O primeiro quadro da sobreposição após uma troca de papel de parede, uma alternância claro/escuro (papéis de parede dinâmicos), uma mudança de tela ou a inicialização decodificava a miniatura do papel de parede de cada tela — 30–150 ms por tela com um HEIC grande — e lia os metadados do Store de papéis de parede na thread principal dentro desse mesmo quadro. Agora ambos são preparados em segundo plano assim que o papel de parede ou a configuração de telas muda (e na inicialização), de modo que o primeiro quadro da sobreposição os encontra prontos.
- Um papel de parede escolhido nos Ajustes do Sistema não aparecia nas telas em miniatura da sobreposição até que o painel de Papel de Parede fosse fechado. O macOS envia a notificação de mudança da imagem da mesa antes de os Ajustes do Sistema gravarem a nova escolha no Store de papéis de parede, então o Tiley lia — e armazenava em cache — o papel de parede anterior; e, para uma imagem personalizada, deixava a miniatura (desatualizada) do Store sobrescrever o caminho real da imagem. Agora o Tiley prefere o caminho real para imagens personalizadas, observa o arquivo do Store e resolve novamente quando ele muda, e confere de novo dois segundos após cada notificação.

### Removido

- Removida uma mensagem de status interna que era gravada a cada ação de layout mas nunca exibida na interface (um resquício de uma interface anterior), junto com suas onze chaves de localização agora não utilizadas em todos os idiomas. Sem mudanças visíveis de comportamento.

## [5.2.1] - 2026-07-31

### Corrigido

- Corrigido: as imagens de papel de parede em cache agora são reduzidas para a resolução de pré-visualização do overlay, em vez de permanecerem na resolução completa da foto da área de trabalho. Isso reduz de forma significativa a memória residente e o pico de memória ao abrir o Tiley com papéis de parede personalizados grandes, sem alterar o posicionamento do papel de parede nem a detecção de cor da barra de menus.

## [5.2.0] - 2026-07-31

### Corrigido

- Corrigido: o ícone do app do Tiley parecia semelhante demais ao ícone do sistema operacional de desktop mais usado.
- Corrigido: imagens de papel de parede em cache de monitores desconectados ou reconfigurados podiam permanecer na memória até que a versão da imagem da área de trabalho mudasse. Agora o Tiley invalida imediatamente o cache de papéis de parede quando a configuração de telas muda, reduzindo o uso desnecessário de memória após conectar, desconectar ou reorganizar monitores.
- Corrigido: após baixar uma atualização, a caixa de diálogo "Instalar e reiniciar" do Sparkle podia ficar atrás da janela de configurações. O código que restaurava a janela de configurações rodava no callback `didFinishUpdateCycleFor` do Sparkle, mas esse callback dispara quando o ciclo de verificação do appcast termina — logo após o usuário clicar em "Instalar atualização" na primeira caixa de diálogo, muito antes de o download terminar e a caixa de diálogo de instalação/reinício aparecer. A janela de configurações estava sendo trazida para a frente dessas caixas ainda ativas. A restauração agora aguarda `standardUserDriverWillFinishUpdateSession` sempre que o Sparkle tiver mostrado interface para o usuário; o `didFinishUpdateCycleFor` só restaura a janela de configurações em verificações de fundo realmente silenciosas, sem nenhuma caixa de diálogo do Sparkle.
- Corrigido: aplicar um layout logo após abrir o Tiley podia selecionar as janelas na ordem anterior à atualização. A lista de janelas da barra lateral é preenchida primeiro pelo cache e só é substituída quando a captura autoritativa em segundo plano chega, então um atalho de predefinição ou um clique na pré-visualização do layout disparado nesse intervalo escolhia os alvos pela ordem desatualizada. Agora a aplicação do layout aguarda a lista de janelas atualizada e roda sobre ela; as janelas do próprio Tiley são ocultadas de imediato, mantendo a sensação de resposta rápida.
- Ao abrir o Tiley, as minijanelas da pré-visualização do minidesktop podiam ser desenhadas brevemente em posições desatualizadas, pulando para as corretas um ou dois segundos depois, quando a captura assíncrona de janelas era concluída. O primeiro quadro é desenhado a partir da lista de janelas em cache, que guarda apenas as coordenadas do momento em que foi criada; janelas movidas ou redimensionadas enquanto a interface do Tiley estava fechada apareciam, portanto, na posição antiga. O realinhamento do cache feito antes da exibição agora também atualiza as coordenadas (e a tela correspondente) de cada janela a partir do mesmo snapshot rápido do CGWindowList já usado para a ordem Z, de modo que as minijanelas aparecem nas posições atuais desde o primeiro quadro.

## [5.1.9] - 2026-05-12

### Corrigido

- Corrigido um problema em que um ícone do Tiley aparecia no Dock ao iniciar (sem o ponto indicando que está em execução) mesmo com "Mostrar ícone no Dock" desativado. A causa era uma cena `Window` âncora oculta do SwiftUI que registrava brevemente uma janela de 0×32 pt no macOS durante a inicialização — tempo suficiente para que uma entrada fosse adicionada ao Dock antes de a política `.accessory` entrar em vigor. A cena âncora foi removida; a política de ativação agora é gerenciada inteiramente por `applicationWillFinishLaunching` e pela lógica existente de `applyDockIconVisibility`.

## [5.1.8] - 2026-05-09

### Corrigido

- Em janelas agrupadas com bordas superior e inferior alinhadas, as alturas agora se mantêm alinhadas também ao crescer, e não apenas ao encolher. O setter de frame da janela seguidora aplicava primeiro o tamanho e depois a posição; um crescimento que empurraria a borda superior para além da barra de menus ou do limite da tela era silenciosamente limitado pelo app — a base seguia o arrasto, mas a borda superior escorregava para baixo. Agora o setter pré-posiciona a seguidora no seu destino final pretendido antes de aplicar o novo tamanho; um ajuste final de posição baseado no tamanho que o app de fato aceitou mantém a borda de contato fixa mesmo quando restrições mín./máx. entram em ação. Ao soltar o arrasto, um passo final de "snap" alinha as bordas superior/inferior (ou esquerda/direita) que o cache considerava alinhadas exatamente às da fonte, eliminando defasagens residuais de poucos pixels.

## [5.1.7] - 2026-05-08

### Removido

- Foi removido o caminho de fallback que preenchia o fundo das mini telas da grade de layout com o cache BMP do agente de papel de parede, usado para tipos de papel sem miniatura dedicada (biblioteca do Fotos, Aerial etc.). Esse cache fica dentro do container de `com.apple.wallpaper.agent` (`~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/`) e, no macOS Sequoia, acessá-lo dispara o novo aviso de permissão "Dados de apps", uma exigência alta demais para uma imagem de fundo puramente decorativa. Agora o Tiley se apoia somente na URL pública da imagem da mesa e em `/System/Library/Desktop Pictures/.thumbnails/`; quando nenhuma das duas fontes resolve o papel de parede, a imagem de fundo é omitida e apenas a grade, a cor de preenchimento e o layout da tela continuam sendo desenhados.

## [5.1.6] - 2026-05-08

### Corrigido

- No primeiro lançamento em um Mac novo, não aparece mais uma caixa de diálogo de permissão espúria de "Recepção de teclas" (Monitoramento de entrada). A caixa surgia porque o Tiley criava um `CGEventTap` para monitorar cliques do mouse antes de a Acessibilidade ser concedida; o tap agora é criado de forma adiada, no exato momento em que a Acessibilidade passa a ser concedida, fazendo com que o macOS trate a criação do tap como coberta pela aprovação de Acessibilidade e dispense completamente o aviso de Monitoramento de entrada.
- Após conceder a Acessibilidade pela primeira vez e voltar para o Tiley, a lista de janelas da barra lateral e a grade de layout agora são preenchidas imediatamente, em vez de ficarem presas em "Nenhuma janela". Antes, o cache da lista de janelas era preenchido com um resultado vazio enquanto a Acessibilidade estava ausente e depois tratado como autoritativo após a permissão; agora a atualização do cache é ignorada sem Acessibilidade e, no caminho de retorno após a concessão, a grade de layout é ativada explicitamente e uma nova captura é disparada.

## [5.1.5] - 2026-05-08

### Corrigido

- O emblema de agrupamento de janelas (o círculo flutuante mostrado entre janelas vinculadas) não fica mais sobreposto a sheets e diálogos modais apresentados pelo próprio aplicativo. A detecção cobre os subpapéis da janela em foco `AXDialog` / `AXSystemDialog`, o papel `AXSheet` e janelas pai com um sheet anexado; enquanto qualquer um deles estiver visível, o emblema é ocultado e volta a aparecer depois que o modal é fechado.

## [5.1.4] - 2026-05-03

### Corrigido

- Depois de desagrupar explicitamente um par de janelas, afastá-las e voltar a aproximá-las até as bordas se tocarem, o emblema candidato de "formar grupo" volta a aparecer. Antes, o desagrupamento interrompia a observação de Acessibilidade nas janelas que ficavam isoladas, de modo que os movimentos manuais subsequentes deixavam de disparar os eventos que alimentam a detecção de adjacência — o emblema silenciosamente deixava de reaparecer até que outro evento (troca de Space, ativação de um app, etc.) reativasse a atualização do cache da lista de janelas.

## [5.1.3] - 2026-04-27

### Corrigido

- A janela de Ajustes agora abre centralizada na tela inteira em vez de no centro da área visível sem o Dock, aparecendo no centro real da tela independentemente da posição do Dock.

## [5.1.2] - 2026-04-26

### Corrigido

- Não aparece mais o emblema candidato "Criar grupo" entre janelas já vinculadas — nem entre pares que ficam adjacentes por acaso após uma predefinição, nem entre pares pertencentes a dois grupos distintos, nem entre pares já conectados pelo mecanismo de satélites das predefinições com apps atribuídos.
- Os emblemas de grupos vinculados agora aparecem apenas para o grupo que contém a janela em primeiro plano (ou conectado a ela via satélites). Os emblemas de grupos de fundo não relacionados, que apenas compartilhavam o app da janela focalizada, sumiram.
- Trazer uma janela agrupada para a frente — clicando, selecionando-a na barra lateral do Tiley e pressionando Enter, ou via click-to-activate do macOS — agora traz o grupo inteiro junto de forma confiável. Foram corrigidos vários casos em que uma janela irmã do grupo permanecia atrás de outra janela (janelas de outro app intercaladas entre membros do grupo, o app reascendendo a janela principal anterior em vez da selecionada e a animação de restauração de deslocamento fora da tela do próprio Tiley sendo interpretada como arrasto manual).

### Alterado

- Ao aplicar uma predefinição de layout cujo par agrupado afeta uma janela que já faz parte de um grupo existente, tudo não é mais mesclado em um único grupo maior. A janela compartilhada se torna uma "âncora de janela" e cada um de seus parceiros (os outros membros do grupo preexistente e o parceiro recém-adicionado) é registrado como satélite, espelhando o modelo já usado para slots de predefinição atribuídos a aplicativos. Cada par mantém seu próprio layout lembrado: clicar em um satélite traz a âncora para frente e restaura as posições salvas desse par; clicar na âncora faz com que o satélite atualmente mais à frente se torne o par ativo. Exemplo: com um grupo A↔B existente, aplicar uma predefinição que pareia C↔A deixa A↔B intacto — clicar em B traz A de volta ao lado de B no layout A↔B original; clicar em C posiciona A ao lado de C no layout C↔A da predefinição. O par ativo exibe o emblema de vínculo como antes; alternar entre satélites reconstrói dinamicamente o grupo espacial

## [5.1.1] - 2026-04-25

### Adicionado

- O menu ao passar o cursor sobre a insígnia de vínculo de um grupo de janelas agora tem um terceiro botão ao lado do de troca: **Igualar altura das janelas** (para pares esquerda/direita, ícone de setas para cima/baixo) ou **Igualar largura das janelas** (para pares superior/inferior, ícone de setas para esquerda/direita). Alinha os dois lados da insígnia (todos os membros do grupo, classificados pela linha de contato) no eixo perpendicular. "Ambos os lados" não se refere apenas às duas janelas diretamente conectadas pela insígnia, mas sim a **todos os membros do grupo do mesmo lado da linha de contato** — incluindo "irmãs" que não estão diretamente vinculadas entre si mas compartilham uma borda pai (exemplo: em cima `[A]`, embaixo `[B]` e `[C]` ambas tocando a borda inferior de A sem estarem conectadas entre si → clicar em "Igualar largura" na insígnia A↔B trata `{B, C}` como um único lado e B+C juntas passam a ter a mesma largura que A). Em cada lado as janelas são ordenadas e reorganizadas borda a borda: as bordas mais externas se ancoram à envoltória externa e janelas adjacentes se encontram no ponto médio das bordas originais, portanto bordas compartilhadas já alinhadas permanecem onde estão, enquanto um vão ou sobreposição é distribuído igualmente entre as duas. O botão fica oculto quando ambos os lados já estão alinhados e não há vão ou sobreposição interna a corrigir
- As insígnias candidatas a "formar grupo" agora também aparecem quando você move ou redimensiona uma janela manualmente de modo que sua borda encoste na borda de outra janela — não apenas após aplicar um layout do Tiley. A insígnia surge no instante em que você solta o mouse (durante o arrasto/redimensionamento ela permanece oculta); ao clicar nela, o par é vinculado em um grupo de janelas exatamente como a insígnia candidata pós-layout
- Ao clicar numa insígnia candidata a "formar grupo", o menu de hover (Desagrupar / Trocar / Igualar altura ou largura) aparece imediatamente no mesmo instante em que o grupo é criado — não é mais preciso afastar o cursor da insígnia e voltar a passá-lo por cima
- O menu de hover (a cápsula de ações) agora aparece e some com efeito de fade-in/fade-out, em vez de surgir ou desaparecer de uma vez. Durante o fade-out o painel da insígnia mantém o tamanho expandido para que a cápsula não seja cortada; passar o cursor de novo durante a animação cancela o recolhimento
- Dois botões novos no menu de hover da insígnia vinculada: **Preencher a largura da tela** (ícone `rectangle.portrait.arrowtriangle.2.outward`) e **Preencher a altura da tela** (ícone `rectangle.arrowtriangle.2.outward`). Eles redimensionam proporcionalmente todas as janelas do grupo de modo que o retângulo envolvente coincida exatamente com a largura ou altura da área visível da tela (excluindo Dock e barra de menus), preservando o espaçamento relativo entre os membros. Cada botão fica oculto quando o grupo já preenche a tela nesse eixo
- Ao passar o cursor sobre a insígnia de vínculo entre duas janelas reais agrupadas, agora aparece um pequeno menu de ações abaixo da insígnia (ou acima, caso abaixo saísse da tela): um botão **Desagrupar** e um botão para trocar as janelas — **Trocar janelas esquerda/direita** ou **Trocar janelas superior/inferior**, conforme a disposição do par. A própria insígnia não se transforma mais em botão de desagrupar; passa a servir apenas como indicador visual do vínculo. Ao realizar a troca, todos os outros vínculos que essas duas janelas tenham com terceiras janelas também são removidos, deixando apenas um grupo limpo formado pelas duas janelas trocadas

### Corrigido

- Ao aplicar um preset de layout com múltiplos retângulos, se uma janela não puder encolher até seu retângulo alvo por causa do tamanho mínimo do app, a largura ou altura da janela vizinha agora é ajustada automaticamente para que a borda compartilhada permaneça alinhada (preservando o espaçamento do preset). Antes ocorriam sobreposições ou vãos desalinhados
- O indicador de agrupamento da barra lateral agora também exibe os vínculos satélites de slot de aplicativo que não fazem parte do grupo espacial atualmente ativo. Quando um preset com retângulos atribuídos a aplicativos e pares agrupados é aplicado, a janela do lado não atribuído é registrada como satélite usando o bundle ID do aplicativo atribuído. Se o preset (ou outro com o mesmo aplicativo âncora) for reaplicado usando uma janela diferente, o par anterior sai do `WindowGroup` espacial, mas seu vínculo satélite (a ligação de trazer ao primeiro plano ao clicar) é preservado. Até agora esses vínculos "em segundo plano, porém ainda ativos" não apareciam na barra lateral; agora são exibidos junto aos parceiros espaciais ativos como ícones de aplicativo parceiro, e cada um pode ser desvinculado individualmente com a mesma interação hover → clique. Isso vale também quando uma única janela é satélite de vários aplicativos âncora, ou quando o mesmo bundle de uma janela âncora tem vários satélites registrados

### Alterado

- Ao aplicar uma predefinição de layout que encosta uma janela em uma borda da tela, agora apenas as adjacências de grupo do lado da janela redimensionada que fica rente à borda da tela são desfeitas — as adjacências nas outras bordas são preservadas. Por exemplo, com um par horizontal A↔B e um par vertical A↔C, aplicar "Preencher largura da tela" em A desfaz o vínculo A↔B (a borda direita de A passa a ser a borda direita da tela), enquanto o vínculo A↔C é preservado enquanto a borda inferior de A não tocar o fundo da tela. Antes, qualquer redimensionamento do Tiley que afetasse apenas parte de um grupo dissolvia o grupo inteiro, independentemente das bordas envolvidas
- O indicador de agrupamento da barra lateral foi redesenhado. Em vez de um selo de link flutuando entre as linhas, agora cada linha de janela agrupada mostra à direita — logo antes do selo de índice — os ícones dos aplicativos de todas as janelas parceiras vinculadas, lado a lado. Ao passar o cursor sobre um ícone parceiro, a linha da janela parceira é destacada na barra lateral e, ao mesmo tempo, esse ícone (assim como o ícone correspondente na linha da parceira) muda para um estado vermelho `x`, deixando claro de imediato quais duas janelas estão envolvidas. Um clique no estado `x` desvincula apenas essa conexão; assim, quando uma janela está vinculada a várias outras, os vínculos podem ser desfeitos um a um. O espaço do selo de índice é sempre reservado, então as linhas permanecem alinhadas mesmo quando nenhum índice é exibido

## [5.1.0] - 2026-04-25

### Adicionado

- Novo preset de layout padrão "Centro": uma grade 4×4 com a região central 2×2 selecionada, vinculado ao atalho `C`
- Nova linha "+" no final da lista de presets de layout. Clicar nela cria um preset chamado "Novo preset de layout" e entra imediatamente no modo de edição
- Agora é possível definir agrupamento diretamente ao editar um preset de layout: um selo `link.badge.plus` aparece em cada borda compartilhada entre regiões do preset; clique para marcar o par como agrupado (o selo muda para o estado vinculado; ao passar o mouse, ele alterna para o ícone de remoção). Ao passar o mouse sobre um preset na barra lateral, os selos vinculados também aparecem sobre a pré-visualização, deixando claro de relance quais regiões serão agrupadas. Ao aplicar o preset, as janelas correspondentes já começam agrupadas, sem cliques adicionais
- Agora os retângulos de um preset de layout podem ser vinculados a um aplicativo específico. No editor de presets, cada retângulo exibe um selo `macwindow.badge.plus` — clique para escolher um aplicativo em execução (ou navegue pelo sistema de arquivos via "Outro aplicativo…"). Retângulos atribuídos são exibidos como uma janela em miniatura com o ícone do aplicativo em vez do número de índice; passe o mouse e clique no ícone para remover a atribuição. Ao aplicar o preset, um retângulo atribuído sempre recebe a janela mais à frente do aplicativo vinculado (iniciando-o e aguardando até 30 s se necessário). Se o aplicativo estiver em execução mas sem janelas, uma notificação do sistema é exibida. Quando um par agrupado tem exatamente um lado atribuído, a janela que cai no lado não atribuído é vinculada à janela do aplicativo atribuído como "satélite" durante a sessão: clicar em uma traz a outra para a frente também

### Alterado

- `debugLog` agora usa `@autoclosure`, de modo que, quando o log de depuração está desativado, não há qualquer custo de interpolação de string das mensagens de log

### Corrigido

- Os selos de vínculo para agrupamento de janelas não aparecem mais sobre janelas que estão totalmente escondidas atrás de outra janela. Após aplicar um layout a muitas janelas, os selos são exibidos apenas entre as janelas visíveis (à frente); as janelas ocultas ficam excluídas dos candidatos ao agrupamento até serem trazidas à frente

### Removido

- Removido o preset temporário "Última seleção" que era adicionado automaticamente após aplicar um layout. Novos presets agora são criados explicitamente pela linha "+"

## [5.0.1] - 2026-04-23

### Corrigido

- Corrigido o tremor de janelas agrupadas ao voltar para o app via Cmd+Tab. A vinculação de ordem Z podia disparar antes do macOS terminar de trazer as janelas do app para frente, fazendo um membro do grupo sem foco aparecer brevemente à frente do membro com foco

## [5.0.0] - 2026-04-22

### Adicionado

- Agrupamento de janelas adicionado. Após aplicar uma predefinição de layout com várias janelas, um crachá de vínculo (`link.badge.plus`) aparece no ponto médio de qualquer borda em contato. Clicar no crachá agrupa as janelas: arrastar uma janela move todas as membros juntas, redimensionar a borda compartilhada redimensiona a janela adjacente em sentido oposto e trazer um membro para frente eleva os outros logo abaixo. Ao passar o mouse sobre o crachá aparece um ícone para dissolver o grupo; fechar uma janela do grupo também o dissolve automaticamente
- Crachá de vínculo na barra lateral: na barra lateral da janela principal, agora aparece um pequeno indicador de vínculo entre linhas consecutivas de janelas agrupadas, permitindo identificar num relance quais janelas estão conectadas. Se uma janela agrupada fosse separada da sua parceira por um bloco de cabeçalho do app, ela é retirada desse bloco e posicionada logo abaixo da parceira para manter o vínculo visível

### Corrigido

- Corrigido o problema em que as prévias ao passar o mouse e ao arrastar na grade da janela principal usavam o estilo de retângulo da edição de predefinição (preenchimento tingido, sem barra de título) também durante a aplicação normal de um layout; fora da edição de uma predefinição, a janela em miniatura com ícone do app, nome do app e título da janela agora é exibida corretamente
- Corrigido o posicionamento incorreto ocasional de uma das duas janelas ao aplicar um layout lado a lado a uma seleção múltipla. A animação que deslocava temporariamente para baixo as janelas que ocultavam a janela selecionada continuava em execução depois da aplicação do layout e sobrescrevia as posições finais
- Corrigido o problema em que, após aplicar um layout lado a lado, uma janela já posicionada podia deslizar lentamente para o canto inferior direito. A limpeza adiada que ocorre depois de ocultar a janela principal podia iniciar uma animação de restauração enquanto a janela recém-posicionada ainda constava na lista de janelas afastadas, arrastando-a de volta para sua posição anterior ao deslocamento

## [4.4.3] - 2026-04-20

### Alterado

- Ao editar uma predefinição de layout, as prévias de passagem do mouse e de arrasto na grade agora usam o mesmo estilo de retângulo das seleções confirmadas: tingidas com a cor do próximo índice e exibindo centralizado o número de índice que será atribuído, sem barra de título e sem botão de exclusão. Além disso, passar o mouse sobre uma célula vazia mostra uma prévia de retângulo do tamanho de uma célula mesmo quando outros layouts já estão registrados
- Durante a edição de uma predefinição, tanto o retângulo ao passar o mouse quanto o retângulo arrastado agora exibem centralizado o número de índice que será atribuído ao confirmar (com a mesma aparência do retângulo confirmado), incluindo a prévia de uma única célula ao passar o mouse. As prévias de predefinições de layout (passar o mouse sobre uma predefinição na barra lateral e a sobreposição de prévia em tela cheia ao aplicar predefinições de seleção múltipla) continuam exibindo os números de índice

### Corrigido

- Corrigido o salto da janela principal para o centro da tela ao adicionar ou editar uma grade em uma predefinição de layout quando "Mostrar perto do ícone ao clicar" estava ativado; a janela agora permanece ancorada perto do ícone da barra de menus
- Corrigido o problema em que retângulos de seleção confirmados eram exibidos ocasionalmente sem preenchimento e sem borda (apenas com o botão de fechar e o rótulo de índice visíveis) quando uma predefinição de layout continha várias seleções

## [4.4.2] - 2026-04-19

### Corrigido

- Corrigida a ordem de empilhamento invertida ao aplicar um layout a várias janelas selecionadas; a primeira janela selecionada (principal) agora fica em primeiro plano como esperado

## [4.4.1] - 2026-04-18

### Alterado

- Ao abrir pelo atalho, a visualização da tela em miniatura – e não a janela inteira – agora fica centralizada no monitor. A referência é o quadro completo da tela (incluindo barra de menus e Dock), de modo que a miniatura permanece centralizada mesmo com o Dock à esquerda ou à direita
- Quando "Mostrar perto do ícone ao clicar" está ativado, clicar no ícone da barra de menus agora alinha o centro da visualização em miniatura (e não o da janela inteira) ao ícone; o triângulo do balão continua apontando diretamente para o ícone

## [4.4.0] - 2026-04-17

### Alterado

- Melhoria das visualizações de janelas em miniatura na grade: ao passar o mouse e arrastar, são exibidas janelas em miniatura coloridas em vez de retângulos de cor sólida, telas secundárias exibem o mesmo estilo de janela em miniatura da tela principal, e as células da grade permanecem visíveis durante o arrasto
- Simplificação da sobreposição em telas não alvo: removido o ícone de arranjo de telas em miniatura, exibindo apenas uma grande seta direcional centralizada
- As interações de grade em janelas de telas secundárias agora respondem ao primeiro clique sem exigir um clique adicional para obter foco

### Corrigido

- Corrigido o triângulo do balão de fala que desaparecia e a janela que se deslocava para cima antes da animação de esmaecimento ao fechar o Tiley clicando no ícone da barra de menus. O triângulo agora permanece visível durante o esmaecimento, igual ao comportamento ao clicar em outra janela
- Corrigido o triângulo do balão de fala que aparecia incorretamente nas janelas de telas secundárias ao abrir o Tiley pelo ícone da barra de menus
- Corrigido os botões da barra de ferramentas desabilitados na inicialização quando a lista de janelas já estava disponível antes da exibição da barra lateral

## [4.3.9] - 2026-04-14

### Adicionado

- Adicionado um ponteiro triangular estilo balão de fala na borda da janela principal voltada para o ícone da barra de menus ou do Dock quando "Mostrar perto do ícone ao clicar" está ativado

### Corrigido

- Corrigido um problema em que, ao abrir o Tiley logo após alternar de app e antes que o cache em segundo plano da lista de janelas fosse atualizado, a barra lateral mostrava brevemente no topo o app anteriormente em primeiro plano ou, ocasionalmente, selecionava uma janela que não era a mais à frente

## [4.3.8] - 2026-04-13

### Adicionado

- Animação suave de aparecimento/desaparecimento gradual ao exibir e ocultar a janela de sobreposição usando Core Animation acelerada por GPU

### Corrigido

- Os botões da barra de ferramentas ficavam desativados na primeira execução até que a seleção de janela fosse alterada na barra lateral

## [4.3.7] - 2026-04-10

### Alterado

- Melhoria significativa na velocidade de abertura da janela de sobreposição. Operações pesadas (consultas Accessibility/CoreGraphics, construção da pré-visualização de layout) são executadas de forma adiada após a exibição da janela, e a lista de janelas pré-armazenada em cache é mantida entre sessões

## [4.3.6] - 2026-04-10

### Adicionado

- Adicionada opção para mostrar a janela do Tiley perto do ícone da barra de menus ou do Dock ao clicar (ativada por padrão)

## [4.3.5] - 2026-04-09

### Corrigido

- Corrigida a inconsistência do raio de canto da janela em miniatura na minitela durante as pré-visualizações de hover e arrasto para corresponder à janela selecionada

## [4.3.4] - 2026-04-09

### Corrigido

- A janela de configurações é fechada antes da verificação de atualizações do Sparkle para evitar que a pré-visualização da grade ao passar o mouse a traga para frente e oculte os diálogos do Sparkle. A janela de configurações é restaurada após o término do ciclo de atualização

## [4.3.3] - 2026-04-09

### Adicionado

- Agora é possível mover a janela arrastando a barra de dicas do teclado, as áreas de barra de menus/Dock da minitela, regiões vazias da barra lateral e espaços entre botões da barra de ferramentas

### Corrigido

- Arrastar na parte superior da grade movia a janela em vez de selecionar células

## [4.3.2] - 2026-04-08

### Corrigido

- Corrigido um bug onde duas janelas podiam ser selecionadas ao invocar o Tiley logo após trocar de janela

## [4.3.1] - 2026-04-07

### Corrigido

- Ocultar a janela de configurações quando o Sparkle exibe o diálogo de atualização, evitando que a pré-visualização da grade ao passar o mouse traga a janela de configurações para frente e bloqueie o botão "Instalar e reiniciar"

## [4.3.0] - 2026-04-07

### Alterado

- A busca na barra lateral agora usa correspondência por subsequência — digitar "f1" encontra "Finder Users1" mesmo com caracteres não consecutivos
- A busca na barra lateral também pesquisa o nome original (não localizado) do app, então "ai" encontra "Mail" mesmo quando o app é exibido com um nome localizado

### Corrigido

- Corrigido um problema onde fechar uma janela às vezes causava a seleção múltipla involuntária das janelas seguintes na barra lateral
- Corrigido um problema onde a janela em miniatura na grade não era atualizada para o novo alvo após fechar uma janela

## [4.2.3] - 2026-04-05

### Adicionado

- O menu de contexto agora inclui "Fechar N janelas" quando várias janelas estão selecionadas; apps com apenas uma janela são encerrados em vez de apenas fechar a janela, e a seleção é redefinida para uma única janela após o fechamento

### Alterado

- Ao passar o mouse sobre uma célula da grade, agora é exibida uma pré-visualização de janela em miniatura com o ícone do app e a barra de título, em vez de um simples retângulo azul, unificando a aparência com a seleção por arrasto
- Ao fechar uma janela pelo menu de contexto ou pela tecla "/", a barra lateral agora seleciona o item abaixo da janela fechada; se não houver item abaixo, seleciona o item acima

### Corrigido

- Janelas deslocadas (não alvo) agora retornam corretamente à posição original após aplicar um layout de múltiplas janelas
- "Última seleção" agora é exibida corretamente mesmo quando seu layout principal corresponde a um preset que possui layouts secundários (por exemplo, selecionar manualmente a metade superior não é mais ocultado pelo preset "Metade superior" que também inclui um layout secundário para a metade inferior)
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
