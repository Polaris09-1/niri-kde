# Galería: optimización del tiempo de apertura

Fecha: 2026-11-10 · Quickshell 0.3.2 · niri 26.04 · Qt Multimedia con FFmpeg 9.0.2 · 24 fondos (todos vídeo mp4)

## Resumen

Desde el atajo hasta ver la galería con todo dentro:

| Qué se ve | Antes | Después |
|---|---:|---:|
| Ventana en pantalla | ~510 ms | **~250 ms** |
| Vídeo moviéndose en la tarjeta central | ~875 ms | **~305 ms** |
| Paleta de colores calculada | ~1350 ms | **~375 ms** |
| Tarjetas con su imagen (fin del fundido) | ~1130 ms | **~510 ms** |

Sin quitar nada: mismo aspecto, mismas animaciones, mismo vídeo y la misma calidad. Tres causas, ninguna en el dibujo:

1. **Qt Multimedia probaba todos los codificadores de vídeo por hardware al arrancar** (~225 ms en cada apertura,
   y además abría un contexto CUDA en la GPU NVIDIA). La galería nunca codifica vídeo.
2. **Las tarjetas esperaban a 24 procesos** (`fondo-fotograma.sh`, uno por vídeo) para conocer la ruta de una imagen
   que ya estaba guardada, después de un temporizador de 300 ms: la ventana salía vacía casi medio segundo.
3. **Esperas pensadas para recorrer el carrusel deprisa también se aplicaban al abrir**: 250 ms antes de empezar el
   vídeo, 120 ms fijos para mostrarlo y 200 ms antes de calcular la paleta.

## Cómo se midió

- Una **copia** de la galería en una carpeta temporal (`quickshell -p`), con marcas `MEDIR <ms> <etapa>` por
  `console.log`, separadas del resto del registro con `grep`. El módulo real nunca llevó instrumentación.
- Lanzada con **el mismo entorno que `fondo-arrancar.sh`** (VA-API en la Radeon, misma detección de nodos).
- 5 arranques por variante; los números son medianas en ms **desde que nace el proceso**. El reloj es `Date.now()`
  en QML y `date +%s%3N` en el lanzador: el mismo reloj del sistema (no monotónico, pero en ventanas de 1-2 s
  la diferencia es despreciable).
- Etapas: comienzo de la evaluación del QML, `Component.onCompleted`, respuesta de `Principal.pedirEnfocada()`,
  lectura de `wallpaper-actual`, `FolderListModel` listo, `root.abrir()`, primer cuadro presentado
  (`frameSwapped` de la ventana), inicio de la vista previa, `play()`, primer fotograma de vídeo
  (`videoSink.videoFrameChanged`), vídeo mostrado (`listo`), imagen de la tarjeta central cargada (tras su
  fundido de 180 ms) y paleta lista.
- Un temporizador de 10 ms anotaba los bloqueos del hilo principal de más de 40 ms.
- El tramo del atajo hasta que nace `quickshell` (`galeria-abrir.sh` + `fondo-arrancar.sh`) se midió aparte,
  con un `quickshell` falso que solo anota la hora: **43 ms** (30 de la sonda IPC con la galería cerrada).
- La medición inicial con `time` (~1,68 s) incluía el tiempo de reacción al cerrar: no sirve para comparar.

**Error de medición corregido:** el primer lanzador de pruebas forzaba la redirección de nodos de render de
`fondo-arrancar.sh` con el orden antiguo de las GPU. Hoy `renderD128` es la Radeon y `renderD129` la NVIDIA, y
el script real lo detecta bien (no redirige nada). Forzarlo añadía ~340 ms falsos. Esas medidas se descartaron.

### Tabla (ms desde que nace el proceso; sumar ~43 ms para contar desde el atajo)

| Métrica | Antes | Solo cambio 1 | Después |
|---|---:|---:|---:|
| Inicio del proceso (atajo → `quickshell`) | 43 | 43 | 43 |
| QML empieza a evaluarse | 417 | 152 | 155 |
| Configuración cargada (`onCompleted`) | 432 | 167 | 170 |
| `root.abrir()` | 442 | 176 | 182 |
| Ventana visible (primer cuadro) | 465 | 200 | 209 |
| Primer fotograma de vídeo decodificado | 752 | 485 | 261 |
| Primer fotograma animado visible (`listo`) | 830 | 565 | **261** |
| Carrusel con imágenes (tarjeta central cargada, fin del fundido) | 1087 | 821 | **465** |
| Paleta de matugen | 1310 | 1008 | **333** |
| Procesos `fondo-fotograma.sh` lanzados | 24 | 24 | **0** |

El carrusel responde al teclado desde `abrir()`. "Carrusel con imágenes" es cuando las tarjetas ya muestran su
imagen. En la tarjeta central se ve antes el vídeo, que va encima de la imagen fija.

## Diagnóstico

### Dónde se iba el tiempo (antes)

Quickshell vacío arranca en ~100 ms. Al quitar partes de la galería una a una:

| Variante | QML listo |
|---|---:|
| Galería completa | ~400 ms |
| Sin la vista previa de vídeo (`PreviaAnimada`) | ~140 ms |
| Sin el carrusel, sin el fondo difuminado, sin chips o sin los iconos de la maqueta | ~390-400 ms (no cuestan) |
| Solo un `MediaPlayer` vacío | ~355 ms |
| Solo un `MediaPlayer` con `QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=` | ~120 ms |

Con el registro de Qt Multimedia activado se ve la causa: al crear el primer `MediaPlayer`, el backend FFmpeg
comprueba los dispositivos de **codificación** (vdpau, cuda, vaapi, qsv, vulkan): *"Device types checked. Spent
time: 225 ms"*. `QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi` ya limitaba la decodificación, pero no esto. Durante
esa prueba, `nvidia-smi` muestra un proceso `quickshell` de 10 MiB en la NVIDIA (el contexto CUDA).

### Lo que no era un cuello de botella

- `FolderListModel` con 24 archivos: listo ~5 ms después de cargar la configuración. Filtros y orden no importan.
- `Principal.pedirEnfocada()` (`niri msg`, ~9 ms) se resuelve en paralelo con lo demás.
- `esperaArranque` (500 ms) solo es una red de seguridad: nunca llegaba a dispararse.
- Shaders, `ShaderEffectSource`, desenfoque y fondo a media resolución: no cuestan al arrancar.
- Quedan **~70-90 ms de bloqueo en el primer cuadro**: es la inicialización gráfica de Qt (contexto y
  pipelines), igual antes y después.
- `fondo-optimizar.sh` con la copia ya hecha: 6 ms. `matugen --dry-run`: 130-145 ms en otro proceso.

## Cambios

### 1. `~/.local/bin/fondo-arrancar.sh`: no probar codificadores (galería y fondo)

`export QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=` (vacía pero definida = ninguno).
**Mejora: ~260 ms** en la ventana y en el vídeo, y la NVIDIA ya no se toca al abrir la galería.
VA-API sigue igual: el vídeo se decodifica en la Radeon como antes.

**Ampliado al módulo `fondo` (2026-11-10, después de que el usuario confirmara la galería):** la variable se
exporta para los dos módulos que arranca el script. `fondo` tampoco codifica nada: las copias optimizadas las
hace `fondo-optimizar.sh` con `ffmpeg` aparte, al que la variable no afecta. Así `fondo` ya no despierta la
NVIDIA al iniciar sesión ni al reiniciarse. Por el mismo mecanismo se ahorran ~225 ms de arranque, aunque en
`fondo` no se midió el tiempo por separado.
Comprobado al reiniciarlo desde niri:
- `nvidia-smi` sin procesos durante el arranque;
- la variable aparece en `/proc/<pid>/environ`;
- `fondo info` muestra el vídeo optimizado y listo;
- el decodificador de la Radeon está en uso (`drm-engine-dec`, 251 ms por segundo);
- todos los dispositivos abiertos son amdgpu.

Respaldo de esta ampliación: `~/respaldos-limpieza/2026-11-10-fondo-codificadores/`.

### 2. `shell.qml`: fotogramas desde la caché, sin procesos

`fondo-fotograma.sh` guarda cada fotograma como `~/.cache/galeria/fotogramas/<md5 de la ruta>.jpg`.
Ahora un segundo `FolderListModel` lee esa carpeta y la galería calcula el nombre con `Qt.md5()`. Usa el
fotograma si existe, no está vacío y no es más viejo que el vídeo: la misma regla que el script. Solo los que
faltan o están viejos pasan por el script, como antes. La galería espera a leer la caché antes de abrirse
(menos de 5 ms) para no mostrar tarjetas vacías. `esperaArranque` sigue como red de seguridad.
**Mejora: tarjetas con imagen ~360 ms antes y 0 procesos en vez de 24** en cada apertura.

### 3. `shell.qml` y `PreviaAnimada.qml`: sin esperas al abrir

- `abrir()` coloca el carrusel en el fondo actual **antes** de marcarse abierta: la vista previa recibe
  directamente la tarjeta buena y no empieza por la primera de la lista.
- `PreviaAnimada`: la primera vez empieza sin los 250 ms de espera. Al recorrer el carrusel la espera sigue igual.
- El vídeo aparece con **su primer fotograma real** (`videoSink.videoFrameChanged`, estando en reproducción), en
  vez de 120 ms fijos después de cargar. Así no hay parpadeo negro, y aparece en cuanto hay imagen.
- Paleta: la primera se calcula sin los 200 ms de espera y solo con la galería abierta (antes podía calcularse
  primero para la tarjeta 0). Al recorrer el carrusel la espera sigue igual.

**Mejora: vídeo visible ~300 ms antes, paleta ~675 ms antes** (sumado al cambio 1).

### Memoria y procesos

- PSS con la galería abierta: ~360 MB (antes ~378 MB).
- Al cerrar, el proceso termina igual que antes, ~540 ms después (450 ms del temporizador más el cierre).

## Pruebas realizadas

- 5 aperturas medidas por variante (tabla de arriba), sin errores ni avisos nuevos en el registro.
- Módulo real lanzado como el atajo (`galeria-abrir.sh`): 24 fotogramas, paleta, vídeo de la tarjeta central desde
  la copia optimizada, `mover 3`, `mover -5` y `mover 1`: el vídeo y la paleta cambian a la tarjeta nueva y
  hay 7 tarjetas visibles con sus opacidades normales.
  El atajo vuelve a cerrar la galería y el proceso termina.
- Entorno del proceso real comprobado en `/proc/<pid>/environ`; `nvidia-smi` sin procesos durante la apertura.
- Caché de fotogramas, con una carpeta de fondos de prueba (vídeos generados con ffmpeg):
  - sin fotograma: el script lo crea y se muestra;
  - con fotograma: no se lanza nada ni se reescribe;
  - vídeo más nuevo que su fotograma: se regenera solo ese;
  - carpeta de caché inexistente: todo pasa por el script, como antes.
- Doble pulsación del atajo con 80 ms entre ellas: una sola instancia. Con 200 y 350 ms, la segunda cierra la
  galería (es un interruptor).
- Las entradas de caché creadas por los vídeos de prueba se borraron.

## Lo que se descartó

- **Cargar la vista previa de vídeo después del primer cuadro (Loader):** habría escondido los 225 ms, pero
  congelando la animación de entrada en vez de quitarlos. El cambio 1 los elimina.
- **Limitar o reordenar `FolderListModel`:** con 24 archivos no cuesta nada medible.
- **Tocar shaders, desenfoque o resolución del fondo:** no intervienen en el arranque.
- **Quitar la sonda IPC de `galeria-abrir.sh`** (30 ms con la galería cerrada): sustituirla por `pgrep` abriría
  carreras entre "arrancando" y "lista para IPC". No compensa por 30 ms.

## Pendiente y recomendaciones no aplicadas

- **Dos lanzamientos en el mismo milisegundo crean dos instancias**, también con la versión original:
  `--no-duplicate` de Quickshell no es atómico (lo indica el error "Could not create path symlink … File exists").
  Con una separación humana (80 ms o más) no pasa. Un `flock` en `galeria-abrir.sh` no sirve tal cual: el
  cerrojo lo heredarían los procesos que la galería lanza aparte (`wallpaper.sh`) y podría bloquear el atajo
  mientras se aplica un fondo.
- **Paletas guardadas en disco** (`~/.cache/galeria/paletas.json`, por ruta y fecha del archivo): la paleta de
  un fondo ya visto saldría al instante al recorrer el carrusel (hoy 200 ms de espera + ~140 ms de matugen).
  No afecta a la apertura, por eso no se hizo.
- Comentarios desactualizados en `fondo-arrancar.sh` y `fondo-optimizar.sh` ("renderD128 es la NVIDIA"): hoy es
  al revés. Los scripts detectan el nodo por su driver y funcionan bien con cualquier orden.

## Cómo deshacerlo

Respaldo de los originales: `~/respaldos-limpieza/2026-11-10-galeria-apertura/`. Los pasos están en su
`COMO-DESHACER.txt`: copiar `shell.qml` y `PreviaAnimada.qml` a `~/.config/quickshell/galeria/` y
`fondo-arrancar.sh` a `~/.local/bin/`.

Para deshacer solo la ampliación al módulo `fondo` (la galería conserva su mejora), sigue
`~/respaldos-limpieza/2026-11-10-fondo-codificadores/COMO-DESHACER.txt`.
