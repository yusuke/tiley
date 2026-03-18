# Registro de cambios

## [Unreleased]

### Mejorado

- La ventana principal se cierra automáticamente cuando Sparkle comienza a descargar una actualización

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
