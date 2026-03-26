# Registro de cambios

## [Unreleased]

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
