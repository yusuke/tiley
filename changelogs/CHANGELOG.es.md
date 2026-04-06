# Registro de cambios

## [Unreleased]

## [4.2.3] - 2026-04-05

### Añadido

- El menú contextual ahora incluye "Cerrar N ventanas" cuando hay varias ventanas seleccionadas; las apps con una sola ventana se cierran completamente en lugar de solo cerrar la ventana, y la selección se restablece a una sola ventana después

### Cambiado

- Al pasar el cursor sobre una celda de la cuadrícula, ahora se muestra una vista previa de ventana en miniatura con el icono de la app y la barra de título, en lugar de un simple rectángulo azul, unificando la apariencia con la selección por arrastre
- Al cerrar una ventana mediante el menú contextual o la tecla "/", la barra lateral ahora selecciona el elemento debajo de la ventana cerrada; si no hay ninguno debajo, selecciona el de arriba

### Corregido

- Las ventanas desplazadas (no objetivo) ahora vuelven correctamente a su posición original tras aplicar un diseño de múltiples ventanas
- "Última selección" ahora se muestra correctamente incluso cuando su diseño principal coincide con un preset que tiene diseños secundarios (por ejemplo, seleccionar manualmente la mitad superior ya no queda oculto por el preset "Mitad superior" que también incluye un diseño secundario de la mitad inferior)
- La superposición de vista previa de la cuadrícula no se mostraba al pasar el cursor sobre la sección de cuadrícula en Ajustes
- La superposición de vista previa de la cuadrícula no se actualizaba en tiempo real al cambiar los valores de filas, columnas o espaciado en Ajustes
- Se sale automáticamente de Mostrar Escritorio y Mission Control al invocar Tiley mediante el atajo global o el icono de la barra de menús
- La ventana de superposición de Tiley ya no aparece en Mission Control / Exposé

## [4.2.2] - 2026-04-04

### Cambiado

- Las ventanas de superposición ahora se pre-renderizan con opacidad cero y se mantienen en pantalla, por lo que mostrar la cuadrícula de diseño solo requiere un cambio de alfa, reduciendo significativamente la latencia percibida
- La ventana de configuración ahora se cierra automáticamente al hacer clic en otra aplicación; Tiley permanece oculto hasta que se presione el atajo global nuevamente

### Corregido

- Corregido que al hacer clic en el icono del Dock con la ventana de configuración abierta se mostraba "Sin ventanas" en lugar de la configuración
- Corregido que la ventana de configuración desaparecía permanentemente al desactivar "Mostrar icono del Dock"
- Corregido que el atajo global dejaba de funcionar después de que la ventana de configuración perdía el foco hacia otra aplicación

## [4.2.1] - 2026-04-04

### Cambiado

- Se añadió un indicador de chevron al botón de redimensionar para dejar claro que abre un menú desplegable
- Se mejoró el timing de la acción de redimensionar para que la ventana de Tiley desaparezca antes de redimensionar la ventana objetivo, haciendo la interacción más intuitiva

## [4.2.0] - 2026-04-04

### Añadido

- Redimensionar ventanas a tamaños predefinidos (16:9, 16:10, 4:3, 9:16) desde el botón de la barra de herramientas o el menú contextual; los tamaños que excedan la pantalla actual se excluyen automáticamente
- Vista previa en vivo al pasar sobre los elementos del menú de redimensionado: superposición a tamaño real en la pantalla destino y vista previa en miniatura en la cuadrícula (mismo estilo que la vista previa de diseños predefinidos)
- Vista previa de ventana en miniatura (con barra de título e icono de la app) durante la selección por arrastre en la cuadrícula

## [4.1.2] - 2026-04-03

### Añadido

- Insignias de índice de orden de selección en el lado derecho de los elementos de ventana de la barra lateral cuando se seleccionan dos o más ventanas

### Cambiado

- La lista de ventanas en la barra lateral ahora se precarga en segundo plano mediante listeners de eventos del espacio de trabajo (activación, inicio y cierre de aplicaciones), por lo que aparece instantáneamente al abrir la superposición
- Mejorado el comportamiento de resaltado de los elementos agrupados por aplicación en la barra lateral. El encabezado de la aplicación solo se muestra como seleccionado cuando todas sus ventanas están seleccionadas, y al pasar el cursor sobre el encabezado se resaltan tanto el encabezado como todas sus ventanas secundarias
- Mejora del comportamiento de salida de pantalla completa: ahora establece el atributo AXFullScreen directamente (con pulsación de botón como respaldo), esperando hasta 2 segundos para que se complete la animación

### Corregido

- Corregido el problema de que la superposición no se abría cuando la aplicación en primer plano no tiene ventanas. Ahora se muestra un mensaje "Sin ventanas" y se desactiva el arrastre
- Corregido que el escritorio del Finder se tratara como una ventana redimensionable. Cuando el escritorio está enfocado, ahora se selecciona la ventana real del Finder más al frente, o se muestra "Sin ventanas" si no existe ninguna
- Corregido el problema de que la superposición no se abría cuando la aplicación en primer plano no tiene ventanas (por ejemplo, Finder sin ventanas abiertas, aplicaciones solo de barra de menú); ahora se recurre a la ventana visible más al frente en la pantalla
- Corregido el problema de que la posición de la ventana no se aplicaba correctamente en pantallas no principales para algunas aplicaciones (p. ej., Notion). Se añadió verificación de posición con reintento tras el redimensionamiento para gestionar aplicaciones que revierten la posición de forma asíncrona

## [4.1.1] - 2026-03-31

### Cambiado

- El atajo predeterminado para seleccionar la siguiente ventana cambió de Tab a Space; la ventana anterior cambió de Shift+Tab a Shift+Space
- Las ventanas desplazadas ahora siempre regresan a su posición original con animación al cerrar la superposición

## [4.1.0] - 2026-03-31

### Añadido

- Cambio de ventana manteniendo teclas modificadoras (estilo Cmd+Tab): tras abrir la superposición, mantenga las teclas modificadoras de alternancia y pulse la tecla de activación repetidamente para recorrer las ventanas; al soltar las teclas modificadoras, la ventana seleccionada pasa al frente; pulse atajos locales de diseño mientras mantiene las teclas modificadoras para aplicar el diseño correspondiente
- Sección de reconocimientos de licencias de terceros en Ajustes (Sparkle, TelemetryDeck)

### Cambiado

- Los paneles de Ajustes y Permisos son ahora ventanas independientes a nivel normal (no flotante), para que los diálogos de actualización de Sparkle y otras ventanas del sistema puedan mostrarse encima
- La barra lateral ahora está siempre visible; se ha eliminado el botón de mostrar/ocultar
- El botón de ajustes se ha movido de la barra inferior al extremo izquierdo de la barra de acciones de la barra lateral
- La vista previa de mini pantalla ahora tiene esquinas redondeadas en los cuatro lados independientemente del tipo de pantalla
- La barra de título de la ventana en miniatura ahora muestra el nombre de la aplicación junto al título de la ventana
- La insignia "Actualización disponible" se ha reemplazado por un punto rojo en el botón de ajustes y un tooltip; en el panel de ajustes se muestra un popover en el botón "Buscar actualizaciones"

## [4.0.9] - 2026-03-30

### Corregido

- El redimensionamiento de ventanas fallaba y la posición se desplazaba en ciertas aplicaciones: la posición de rebote cuando el redimensionamiento inicial era rechazado estaba en la parte inferior de la pantalla (sin espacio para expandir), dejando la ventana en una posición incorrecta. Ahora rebota a la parte superior del área visible y restaura explícitamente la posición si el redimensionamiento sigue fallando
- Las ventanas desplazadas a veces no se restauraban a su posición original después de seleccionar una ventana de fondo: la restauración buscaba ventanas en una lista que podía estar desactualizada, causando fallos. Ahora se almacenan las referencias de ventana directamente en los datos de seguimiento de desplazamiento y se aplaza la limpieza hasta que la animación de restauración se complete
- Los botones "Añadir atajo" / "Añadir atajo global" solo respondían a clics cerca del centro: se movieron el relleno y el fondo dentro de la etiqueta del botón para que toda el área visible sea clicable

## [4.0.8] - 2026-03-30

### Corregido

- El panel de permisos ya no flota sobre otras aplicaciones y diálogos del sistema al solicitar acceso de accesibilidad
- La vista previa del fondo de pantalla no se mostraba en macOS Tahoe 26.4: adaptación al cambio de estructura del plist del Store de fondos de pantalla (`Desktop` → clave `Linked`), los fondos de Fotos se cargan desde la caché BMP del agente de fondos de pantalla, se añadió el valor de colocación `FillScreen` (reemplazo de `Stretch` en Tahoe), y se habilitó la configuración del modo de visualización para proveedores de fondos no del sistema
- Los modos de visualización centrado y en mosaico renderizaban las imágenes demasiado pequeñas cuando los metadatos DPI de la imagen no eran 72 (p. ej., capturas de pantalla Retina a 144 DPI); ahora siempre se utilizan las dimensiones reales en píxeles

## [4.0.7] - 2026-03-29

### Corregido

- El modo de visualización de fondo de pantalla en mosaico no se reflejaba en la vista previa de la mini pantalla (el valor de colocación "Tiled" del plist del Store de fondos de pantalla de macOS no se correspondía correctamente)
- Se añadió registro de depuración para la canalización de resolución de fondos de pantalla para ayudar a diagnosticar problemas de visualización

## [4.0.6] - 2026-03-29

### Añadido

- Al pasar el cursor sobre un preset de múltiples diseños, se muestran números de índice de diseño en la cuadrícula de mini pantalla, la vista previa a tamaño real y la lista de ventanas de la barra lateral, permitiendo identificar intuitivamente qué diseño se aplica a cada ventana independientemente de la percepción del color

### Cambiado

- Ajustada la interfaz de la ventana de ajustes para adaptarse al aspecto visual de macOS Tahoe: botones de la barra de herramientas y de acción unificados con forma de cápsula y fondos de hover/pulsación adaptativos al sistema, tarjetas de sección de ajustes con fondo gris claro sin borde, interruptores redimensionados al tamaño de Preferencias del Sistema, y lista de atajos reestructurada con una sección independiente "Atajos para mover a pantalla"

### Corregido

- Las ventanas de la barra lateral que exceden el número de diseños del preset ahora muestran correctamente el color del último diseño en lugar del color de selección principal

## [4.0.5] - 2026-03-29

### Corregido

- Las ventanas desplazadas para mostrar la ventana de destino seleccionada ahora se restauran correctamente a su posición original incluso al ciclar rápidamente
- La vista previa de redimensionamiento de una sola ventana era demasiado tenue en comparación con las vistas previas de diseño de múltiples ventanas; ahora usa la misma opacidad

## [4.0.4] - 2026-03-29

### Añadido

- Al pasar el cursor sobre un preset, la vista previa del mini-pantalla muestra barras de título de ventana (icono de app, nombre de app, título de ventana)

### Cambiado

- La barra de título de la vista previa de diseño a tamaño real ahora muestra el nombre de la app junto con el título de la ventana (formato: "Nombre de App — Título de Ventana")

## [4.0.3] - 2026-03-29

### Añadido

- Los presets con múltiples diseños ahora redimensionan varias ventanas incluso con una sola ventana seleccionada, usando el orden Z real (la ventana más al frente primero)
- Cuando las ventanas seleccionadas son menos que las definiciones de diseño, la ventana seleccionada siempre se trata como primaria y los espacios restantes se llenan por orden Z
- Al pasar el cursor sobre un preset con múltiples diseños, las filas de ventanas afectadas en la barra lateral se resaltan con los colores del diseño (azul, verde, naranja, púrpura)

## [4.0.2] - 2026-03-29

### Cambiado

- La vista previa de diseño a tamaño real ahora solo muestra vistas previas para el número de selecciones definidas en el preajuste (las ventanas seleccionadas adicionales más allá del número de selecciones del preajuste ya no se previsualizan)

## [4.0.1] - 2026-03-29

### Cambiado

- La paleta de colores de selección ahora cicla entre azul, verde, naranja y púrpura (4 colores), de modo que la 5ª selección coincide con la 1ª
- Los preajustes predeterminados (Mitad izquierda/derecha/superior/inferior) ahora incluyen la mitad opuesta como selección secundaria

## [4.0.0] - 2026-03-29

### Añadido

- Preajustes de diseño con selección múltiple: define múltiples regiones de cuadrícula por preajuste para colocar diferentes ventanas en diferentes posiciones
  - Cada arrastre en el editor de preajustes añade una nueva selección (1ª, 2ª, 3ª, ...)
  - Cada selección muestra su número de índice y un botón de eliminar
  - Se previene la superposición de selecciones (con retroalimentación visual)
  - Al aplicar un preajuste con selección múltiple, las ventanas se asignan por orden de selección: la primera ventana seleccionada obtiene la selección 1, la siguiente la selección 2, etc.
  - Las miniaturas y las vistas previas a tamaño real muestran todas las selecciones con colores indexados
  - Las selecciones de cuadrícula tienen un margen de 1pt desde los bordes de pantalla para mejor visibilidad

### Cambiado

- El orden de múltiples ventanas ahora sigue el orden de selección en lugar del orden Z de la barra lateral
  - La primera ventana seleccionada siempre es la principal; las ventanas añadidas con Cmd+clic se agregan en orden
  - La selección por rango con Shift+clic mantiene la ventana ancla como principal
  - Afecta la aplicación de preajustes, traer al frente (Enter) y la vista previa

## [3.4.0] - 2026-03-28

### Añadido

- Selección múltiple de ventanas en la barra lateral con acciones por lotes
    - Clic en el encabezado de la app para seleccionar todas sus ventanas
    - Cmd+clic para añadir/quitar ventanas individuales
    - Shift+clic para seleccionar un rango continuo de ventanas
- Acciones por lotes en selección múltiple: traer al frente (manteniendo el orden Z de la barra lateral), redimensionar/mover a la cuadrícula, mover a otra pantalla, cerrar/salir
- Al cerrar múltiples ventanas seleccionadas, las apps con todas sus ventanas seleccionadas se cierran completamente (excepto Finder)

### Cambiado

- Hacer clic en el encabezado de una app en la barra lateral ahora selecciona todas las ventanas de esa app (antes solo seleccionaba la ventana del frente)
- Al seleccionar una ventana dentro de un grupo de app, el encabezado de la aplicación permanece resaltado
- Para apps que no son Finder con múltiples ventanas, se muestra un botón "Salir de la app" junto al botón "Cerrar ventana" en la barra de acciones
- El tooltip "Cerrar ventana" ahora muestra el nombre de la ventana (ej.: Cerrar "Documento")

## [3.3.2] - 2026-03-28

### Añadido

- Los atajos de teclado para "Seleccionar siguiente ventana", "Seleccionar ventana anterior", "Traer al frente" y "Cerrar/Salir" ahora se pueden configurar en la sección de atajos de las preferencias
- Nuevo elemento de menú contextual "Cerrar otras ventanas de [App]" al hacer clic derecho en una ventana de la barra lateral (solo visible cuando la app tiene varias ventanas)

### Cambiado

- La sección de configuración de atajos ha sido reorganizada en dos grupos: atajos de acción de ventana y atajos de movimiento de pantalla
- Los atajos de movimiento de pantalla ahora son solo globales; se eliminó el soporte de atajos locales y sus opciones de configuración
- En macOS 26 (Tahoe), los botones de la barra de herramientas, el botón de salir, los botones de la barra de acciones y el botón de menú desplegable usan el efecto interactivo de Liquid Glass, siguiendo las Human Interface Guidelines
- El color de fondo de la ventana ahora usa el color del sistema para mayor compatibilidad con los cambios de apariencia de macOS
- Las ventanas desplazadas ahora regresan a su posición original con animación al confirmar una selección, aplicar un diseño o cancelar con Escape

## [3.3.1] - 2026-03-28

### Añadido

- Al seleccionar una ventana en la barra lateral, las ventanas superpuestas se desplazan hacia abajo con una animación suave para hacer visible la ventana seleccionada sin cambiar el foco
- Se muestra un borde resaltado alrededor de la ventana actualmente seleccionada en la barra lateral

### Corregido

- Corregido el orden de ciclo de Tab/flechas para coincidir con el orden de la barra lateral (agrupado por espacio, pantalla y aplicación)
- Las ventanas desplazadas se restauran a su posición original al cancelar (Esc) o cerrar Tiley

## [3.3.0] - 2026-03-27

### Corregido

- Corrección preventiva del uso excesivo de CPU que podía ocurrir en entornos con múltiples pantallas
- Corrección de un bucle de redibujo del icono de la barra de estado que podía causar un uso del 100 % de CPU cuando se mostraba una insignia superpuesta (notificación de actualización o indicador de depuración)
- Las ventanas de Tiley ahora flotan siempre sobre las ventanas normales para no quedar ocultas durante el cambio con Tab

## [3.2.9] - 2026-03-27

### Corregido

- Corregido el orden de ciclo de Tab/flechas para coincidir con el orden de la barra lateral (agrupado por espacio, pantalla y aplicación)

## [3.2.8] - 2026-03-26

### Corregido

- Corregido el problema en la barra lateral donde Tab/flechas alternaban solo entre dos ventanas en lugar de recorrer todas

## [3.2.7] - 2026-03-26

### Corregido

- Corregido un fallo que ocurría al iniciar la app como elemento de inicio de sesión (corrección incompleta en 3.2.6)

## [3.2.6] - 2026-03-26

### Corregido

- Corregido un fallo que ocurría al iniciar la app como elemento de inicio de sesión

## [3.2.5] - 2026-03-26

### Cambiado

- Secciones de atajos y atajos globales unificadas en una sola sección
- Interfaz de configuración de atajos unificada para todos los tipos

### Corregido

- Se corrigió un problema en el que la ventana principal podía permanecer visible cuando la app pasaba a segundo plano
- Corregido el borde de resaltado que se recortaba por las esquinas redondeadas y el notch en pantallas integradas (ahora se dibuja debajo del área de la barra de menús)

## [3.2.4] - 2026-03-26

### Añadido

- Añadidos atajos para mover ventanas entre pantallas (principal, siguiente, anterior, elegir del menú, pantalla específica)

## [3.2.3] - 2026-03-25

### Añadido

- Se añadieron indicadores de flechas direccionales al botón y los elementos de menú "Mover a pantalla", mostrando visualmente la dirección de la pantalla de destino según la disposición física de las pantallas
- Cuando la ventana seleccionada se encuentra en otra pantalla, la superposición de cuadrícula muestra una flecha direccional y un icono de disposición de pantallas en el centro, guiando al usuario hacia la ubicación de su ventana

### Cambiado

- Ajustada la apariencia cuando hay una actualización disponible

## [3.2.2] - 2026-03-25

### Añadido

- Al seleccionar una ventana en la barra lateral, se muestra temporalmente en primer plano para facilitar su identificación; al cambiar a otra ventana o cancelar, se restaura el orden original
- La vista previa de redimensionamiento ahora muestra una barra de título con el icono de la aplicación y el título de la ventana, facilitando la identificación de la ventana que se está organizando

## [3.2.1] - 2026-03-25

### Corregido

- Corregido el problema donde la barra lateral no mostraba ventanas en entornos de múltiples pantallas porque el filtrado de espacios solo consideraba el espacio activo de una única pantalla

## [3.2.0] - 2026-03-25

### Añadido

- Cuando hay varios espacios de Mission Control, la barra lateral muestra solo las ventanas del espacio actual
- La superposición de cuadrícula ahora muestra una vista previa de ventana en miniatura con botones de semáforo, icono de la app y título de la ventana en la posición actual de la ventana de destino

### Cambiado

- La ocultación de la superposición es ahora más responsiva al aplicar diseños o traer ventanas al frente
- Las ventanas en modo de pantalla completa nativo de macOS ahora salen automáticamente de la pantalla completa antes de redimensionarse

## [3.1.1] - 2026-03-24

### Corregido

- Corregido que las miniaturas de fondos de pantalla del sistema se mostraran en mosaico en lugar de relleno
- Corregida la imagen incorrecta en fondos de pantalla dinámicos; añadido soporte de miniaturas para fondos de pantalla basados en proveedores Sequoia, Sonoma, Ventura, Monterey y Macintosh
- El texto de la barra de menú en la vista previa de la cuadrícula ahora se adapta al brillo del fondo de pantalla (negro en fondos claros, blanco en oscuros, como en macOS)

## [3.1.0] - 2026-03-24

### Cambiado

- Reemplazados los menús kebab (…) al pasar el ratón en la lista de ventanas por menús contextuales nativos de macOS (clic derecho)
- Añadidos botones de acción (Mover a pantalla, Cerrar/Salir, Ocultar otras apps) junto al campo de búsqueda de la barra lateral
- Las miniaturas de cuadrícula de los ajustes de diseño ahora reflejan la relación de aspecto del área utilizable de la pantalla (excluyendo la barra de menú y el Dock), adaptándose a la orientación vertical u horizontal.

### Corregido

- Corregido un problema donde el redimensionamiento de ventanas fallaba a veces al mover una ventana a otra pantalla (especialmente a un monitor vertical más alto), mediante la introducción de un mecanismo de reintento en movimientos entre pantallas

### Eliminado

- Eliminados los botones de menú kebab y de cierre que aparecían al pasar el ratón en las filas de la barra lateral (reemplazados por menús contextuales y barra de acciones)

## [3.0.1] - 2026-03-23

### Añadido

- Al traer una ventana al frente con Enter o doble clic, la ventana se mueve a la pantalla donde se encuentra el puntero del ratón si es diferente. Se reposiciona para ajustarse a la pantalla y solo se redimensiona si es necesario.

### Cambiado

- Rendimiento de visualización de la superposición mejorado en ~80% mediante agrupación/reutilización de controladores, carga diferida de la lista de ventanas y renderizado prioritario de la pantalla objetivo
- Se renombró la configuración interna de registro de depuración de `useAppleScriptResize` a `enableDebugLog` para reflejar mejor su propósito

### Corregido

- Se corrigió el redimensionamiento de ventanas que fallaba silenciosamente en la pantalla principal para algunas aplicaciones (p. ej., Chrome). Se aplica el mecanismo de reintento con rebote de las pantallas secundarias también a la pantalla principal
- Se corrigió que al hacer clic en el icono de la barra de menú con la superposición visible se abría la ventana principal en lugar de cerrar la superposición (mismo comportamiento que ESC)

## [3.0.0] - 2026-03-23

### Añadido

- Integración del SDK TelemetryDeck para análisis de uso respetuoso con la privacidad (apertura de superposición, aplicación de diseño, aplicación de preajuste, cambio de ajustes)
- Las ventanas de la barra lateral ahora se agrupan por pantalla y por aplicación; las apps con múltiples ventanas muestran un encabezado con las ventanas indentadas
- Los encabezados de pantalla en la barra lateral ahora tienen un menú con acciones para "Reunir ventanas" y "Mover ventanas a" para gestionar ventanas entre pantallas
- Menú del encabezado de aplicación con "Mover todas las ventanas a otra pantalla", "Ocultar otras" y "Salir"
- Menú de apps con una sola ventana con "Mover a otra pantalla", "Ocultar otras" y "Salir"
- Las pantallas vacías (sin ventanas) ahora se muestran en la barra lateral con su encabezado

### Cambiado

- El fondo de la cuadrícula ahora refleja con precisión la configuración de visualización del fondo de pantalla de macOS (rellenar, ajustar, estirar, centrar y mosaico), incluyendo la escala correcta del mosaico, la proporción de píxeles físicos para el modo centrado y el color de relleno para las áreas de letterbox
- La vista previa de la cuadrícula de diseño ahora muestra la barra de menú, el Dock y la muesca, ofreciendo una representación más precisa de la pantalla real

### Corregido

- Corregido un problema donde la ventana se movía a una posición inesperada después de redimensionar cuando ya estaba en la posición de destino. Evasión de la deduplicación AX mediante pre-desplazamiento
- Reducido el parpadeo al redimensionar en pantallas no principales. Primero se intenta redimensionar en el lugar; solo se recurre a la pantalla principal si falla completamente
- Al recurrir a la pantalla principal, la ventana ahora se coloca en el borde inferior (casi fuera de pantalla) en lugar de en la esquina superior izquierda, minimizando el parpadeo

## [2.2.0] - 2026-03-21

### Cambiado

- Las celdas de la cuadrícula no seleccionadas ahora son transparentes
- La relación de aspecto de la cuadrícula ahora coincide con el área visible de la pantalla (sin barra de menú ni Dock); si la cuadrícula sería demasiado alta, su ancho se reduce proporcionalmente para garantizar que al menos 4 presets sean visibles
- El fondo de la cuadrícula de diseño ahora muestra la imagen de escritorio (semitransparente, esquinas redondeadas)
- Las celdas seleccionadas con arrastre ahora son semitransparentes, mostrando la imagen de escritorio por debajo
- El resaltado al pasar el cursor sobre un preset en la cuadrícula ahora usa el mismo estilo que la selección con arrastre

### Añadido

- La barra lateral de lista de ventanas ahora se muestra en todas las pantallas en configuraciones de múltiples monitores, no solo en la pantalla objetivo
- El estado de la barra lateral (visibilidad, elemento seleccionado, texto de búsqueda) se sincroniza entre todas las ventanas de pantalla
- Registro de depuración de redimensionamiento opcional (`~/tiley.log`) (Ajustes > Depuración)

### Corregido

- Corregido un problema donde la colocación de ventanas usaba geometría de pantalla obsoleta cuando el Dock o la barra de menús se mostraban/ocultaban automáticamente mientras la superposición estaba abierta
- Corregido el redimensionamiento de ventanas fallando en pantallas no primarias en configuraciones de DPI mixto; la ventana se mueve temporalmente a la pantalla primaria para redimensionar y luego se coloca en la posición objetivo
- Corregida la posición no aplicada después del redimensionamiento cuando algunas apps revierten silenciosamente los cambios de posición (solución alternativa de deduplicación AX)
- Cuando el tamaño mínimo de ventana de una app impide el tamaño solicitado, la posición se recalcula para que la ventana permanezca dentro del área visible de la pantalla
- Eliminado el parpadeo visible de ventanas al cambiar ventanas objetivo entre pantallas; las ventanas ya no se recrean al cambiar de pantalla

## [2.1.0] - 2026-03-20

### Añadido

- Doble clic en una ventana de la barra lateral para traerla al frente y cerrar la cuadrícula de diseño
- Menú contextual (botón de puntos suspensivos) en las filas de ventanas de la barra lateral con tres acciones:
  - "Cerrar otras ventanas de [App]" — cierra otras ventanas de la misma app (solo se muestra cuando la app tiene múltiples ventanas)
  - "Salir de [App]" — cierra la aplicación
  - "Ocultar ventanas excepto [App]" — oculta todas las demás aplicaciones (equivalente a Cmd-H), muestra la app seleccionada si estaba oculta
- Las aplicaciones ocultas (Cmd-H) ahora aparecen en la barra lateral como entradas de marcador (solo nombre de la app) y se muestran con 50 % de opacidad
- Al seleccionar una app oculta (Enter, doble clic, redimensionar con cuadrícula/diseño) se muestra automáticamente y se opera sobre su ventana principal

## [2.0.3] - 2026-03-19

### Añadido

- Recordatorios suaves de actualización de Sparkle: cuando una comprobación en segundo plano encuentra una nueva versión, aparece un punto rojo en el icono de la barra de menús y etiquetas "Actualización disponible" junto al botón de engranaje y el botón "Buscar actualizaciones" en los ajustes
- Si el icono de la barra de menús está oculto, se muestra temporalmente con la insignia al detectar una actualización y se oculta de nuevo al finalizar la sesión

### Cambiado

- La ventana de ajustes se oculta cuando Sparkle encuentra una actualización (antes solo al iniciar la descarga) y se restaura al cancelar
- El título de la ventana de ajustes está ahora localizado en todos los idiomas soportados
- El número de versión se movió del título de ajustes a la sección de actualizaciones, junto al botón "Buscar actualizaciones"

## [2.0.2] - 2026-03-19

### Añadido

- Botón de cierre en las filas de la barra lateral de ventanas: al pasar el cursor sobre el nombre de una ventana aparece un botón × para cerrarla
- Ajuste "Cerrar la app al cerrar la última ventana" (Ajustes > Ventanas): cuando está activado (por defecto), cerrar la última ventana de una app cierra la app; cuando está desactivado, solo se cierra la ventana
- El tooltip del botón de cierre muestra el nombre de la ventana; cuando la acción cerrará la app, muestra el nombre de la app
- Atajo de teclado "/" para cerrar la ventana seleccionada (o cerrar la app si es la última ventana y el ajuste está activado)

## [2.0.1] - 2026-03-19

### Cambiado

- Panel de ajustes rediseñado con estilo Tahoe: secciones con fondo de cristal (Liquid Glass en macOS 26+), barra de herramientas compacta con botones de volver/salir, y filas agrupadas estilo iOS con controles en línea

## [2.0.0] - 2026-03-19

### Cambiado

- Se reemplazó el menú desplegable de ventana objetivo por un panel lateral con Liquid Glass (macOS Tahoe); incluye un campo de búsqueda con soporte completo de IME, navegación con teclas de flecha y Tab/Mayús+Tab, y Cmd+F para alternar la visibilidad

### Mejorado

- Las ventanas en el panel lateral se listan en orden Z (de adelante hacia atrás) en lugar de agruparse por aplicación
- Se filtraron las ventanas no estándar (paletas, barras de herramientas, etc.) de la lista de ventanas objetivo para mostrar solo ventanas de documento redimensionables

## [1.2.7] - 2026-03-18

### Mejorado

- La ventana principal se cierra automáticamente cuando Sparkle comienza a descargar una actualización

### Corregido

- Se eliminaron las costuras visibles en la vista previa de restricciones de redimensionamiento cuando se muestran simultáneamente regiones de desbordamiento (rojo) o insuficiencia (amarillo) en ambas direcciones

## [1.2.6] - 2026-03-18

### Corregido

- Al redimensionar una ventana en segundo plano de la misma aplicación mediante el ciclo con Tab, la ventana ahora se trae al frente si quedaría oculta detrás de otras ventanas de esa aplicación

## [1.2.5] - 2026-03-18

### Añadido

- Detección de restricciones de redimensionamiento de ventanas: detecta automáticamente la capacidad de redimensionamiento por eje mediante una verificación rápida de 3 niveles (no redimensionable → botón de pantalla completa → prueba de 1px como respaldo)
- La vista previa de diseño ahora muestra regiones rojas donde la ventana no puede expandirse y regiones amarillas donde no puede reducirse, proporcionando retroalimentación visual sobre las restricciones de tamaño antes de aplicar

## [1.2.4] - 2026-03-17

### Mejorado

- Interfaz de edición de preajustes de diseño refinada: botón de eliminar movido junto al botón de confirmar, botones de edición/acción colocados en una columna dedicada para evitar superposición con los atajos
- La selección de cuadrícula ahora es editable en modo de edición: arrastra sobre la cuadrícula para actualizar la posición del preajuste con vista previa en vivo y resaltado

## [1.2.3] - 2026-03-17

### Mejorado

- Ajuste de la interfaz de edición de preajustes de diseño: el botón de eliminar se muestra como superposición en la vista previa de la cuadrícula, con diálogo de confirmación, fondo opaco al pasar el ratón y estilo de botón uniforme

## [1.2.2] - 2026-03-17

### Cambiado

- Rediseño de la edición de preajustes de diseño para una experiencia de configuración más intuitiva

## [1.2.1] - 2026-03-17

### Correcciones

- Se corrigió el diálogo "Mover a Aplicaciones" que se mostraba incorrectamente en lugar de "Copiar" al iniciar desde un DMG descargado (Gatekeeper App Translocation impedía reconocer la ruta de la imagen de disco)

## [1.2.0] - 2026-03-17

### Añadido

- Cambio de ventana objetivo: pulsa Tab / Mayús+Tab mientras la cuadrícula esté visible para alternar entre las ventanas disponibles
- Menú desplegable de ventana objetivo: haz clic en el área de información del objetivo para seleccionar una ventana desde un menú emergente
- Tab y Mayús+Tab son ahora teclas reservadas y no se pueden asignar como atajos de diseño

## [1.1.8] - 2026-03-16

### Añadido

- Tras copiar desde un DMG, se ofrece expulsar la imagen de disco y mover el archivo DMG a la Papelera
- Detección de un DMG de Tiley montado al iniciar desde /Aplicaciones (por ejemplo, tras copiar manualmente en Finder) con opción de expulsar y mover a la Papelera

## [1.1.7] - 2026-03-16

### Cambiado

- Formato de distribución cambiado de zip a DMG con acceso directo a Aplicaciones y diseño de Finder personalizado (iconos grandes, ventana cuadrada)

### Correcciones

- Se corrigió que "Mover a Aplicaciones" fallaba con un error de volumen de solo lectura al iniciar la app desde un zip descargado sin moverla primero (Gatekeeper App Translocation)
- Se muestra el diálogo "Copiar a Aplicaciones" en lugar de "Mover" cuando la app se inicia desde una imagen de disco (DMG)

## [1.1.6] - 2026-03-16

### Correcciones

- Se corrigió que la ventana de ajustes requería dos activaciones para abrirse en configuraciones multipantalla (icono de barra de menú, Cmd+, y menú Tiley → Ajustes afectados)

## [1.1.5] - 2026-03-16

### Añadido

- Superposición multipantalla: la ventana de cuadrícula de diseño ahora aparece en todas las pantallas conectadas simultáneamente
- Mosaico entre pantallas: arrastra la cuadrícula o haz clic en un preset en una pantalla secundaria para colocar la ventana objetivo en esa pantalla
- La superposición de vista previa aparece en la pantalla donde se muestra la ventana del preset

### Correcciones

- Se corrigió que el diseño maximizado no llenaba toda la pantalla al hacer mosaico entre pantallas de diferentes tamaños
- Se corrigió que los atajos de teclado locales (teclas de flecha, teclas de acceso rápido de presets) no funcionaban tras la segunda activación de la superposición
- Se corrigió que solo algunas ventanas de superposición se cerraban al hacer clic en una ventana de app en segundo plano; ahora todas se cierran juntas
- Se corrigió que el resaltado de hover/selección de presets aparecía en todas las pantallas; ahora solo aparece en la pantalla donde está el cursor del ratón

## [1.1.4] - 2026-03-15

### Correcciones

- Se corrigió que el interruptor "Mostrar icono en Dock" no funcionaba: el icono del Dock no aparecía al activarlo, y al desactivarlo la ventana desaparecía
- Se evita que la app se cierre inesperadamente cuando se cierran todas las ventanas
- Se corrigió que el objetivo de ventana era Tiley al iniciar la app con doble clic; ahora se dirige correctamente a la ventana de la app activa anterior
- Se corrigió que la ventana principal aparecía al iniciar como elemento de inicio de sesión: la ventana ya no se abre en el arranque automático del sistema

## [1.1.3] - 2026-03-15

### Correcciones

- Se corrigió que la superposición de vista previa de cuadrícula a veces permanecía visible en pantalla, causando superposiciones duplicadas apiladas

## [1.1.2] - 2026-03-15

### Añadido

- Localización: español, alemán, francés, portugués (Brasil), ruso, italiano

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Añadido

- Soporte de modo oscuro: todos los elementos de la interfaz se adaptan automáticamente a la configuración de apariencia del sistema

### Cambiado

- La visualización de atajos ahora usa símbolos (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) en lugar de nombres de teclas en inglés

### Correcciones

- La ventana principal ahora se oculta automáticamente cuando Sparkle muestra el diálogo de actualización

## [1.0.1] - 2026-03-15

### Correcciones

- Se añadió la localización faltante para los tooltips de botones de añadir atajo ("Añadir atajo" / "Añadir atajo global")

## [1.0.0] - 2026-03-14

### Añadido

- Solicitud para mover la app a /Aplicaciones cuando se inicia desde otra ubicación
- Indicador global por atajo: cada atajo dentro de un preset de diseño ahora puede configurarse individualmente como global o local
- Botones de añadir separados para atajos regulares y globales, con tooltips popover instantáneos

### Cambiado

- Configuración de atajo global movida de nivel de preset a nivel de atajo
- Los presets existentes con el indicador global legacy a nivel de preset se migran automáticamente

## [0.9.0] - 2026-03-14

- Lanzamiento inicial

### Añadido

- Superposición de cuadrícula para mosaico de ventanas con tamaño de cuadrícula personalizable
- Atajo de teclado global (Mayús + Comando + Espacio) para activar la superposición
- Arrastrar sobre celdas de cuadrícula para definir la región de ventana objetivo
- Presets de diseño para guardar y restaurar disposiciones de ventanas
- Soporte multipantalla
- Opción de iniciar al iniciar sesión
- Localización: inglés, japonés, coreano, chino simplificado, chino tradicional
