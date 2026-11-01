#!/usr/bin/env bash
# wallpaper.sh [archivo [transición x y]]
#   archivo:    imagen, vídeo (mp4/webm/mkv/mov) o GIF. Sin argumentos: vuelve a poner el actual.
#   transición: circulo | ola | barrido | fundido | aleatoria | - (la elegida en la galería)
#   x y:        punto de origen en píxeles (-1 -1 = centro)
# El fondo lo pinta el módulo Quickshell "fondo"; si no está corriendo, se usa swaybg.
set -euo pipefail
GUARDADO="$HOME/.cache/wallpaper-actual"     # el archivo elegido (puede ser vídeo)
FIJA_GUARDADA="$HOME/.cache/wallpaper-imagen" # imagen fija (fotograma si es vídeo/GIF)

if [ $# -ge 1 ]; then
    ARCH="$(realpath "$1")"
    echo "$ARCH" > "$GUARDADO"
else
    ARCH="$(cat "$GUARDADO")"
fi
TIPO="${2:--}"
X="${3:--1}"
Y="${4:--1}"

# Imagen fija para matugen, el difuminado y SDDM
FIJA="$("$HOME/.local/bin/fondo-fotograma.sh" "$ARCH")"
echo "$FIJA" > "$FIJA_GUARDADA"

# 1) Poner el fondo (con transición) en el módulo "fondo"
poner_en_fondo() {
    qs -c fondo ipc call fondo poner "$ARCH" "$TIPO" "$X" "$Y" >/dev/null 2>&1
}
PUESTO=no
if poner_en_fondo; then
    PUESTO=si
elif [ $# -eq 0 ]; then
    # Al iniciar sesión el módulo puede tardar un poco en arrancar
    for _ in 1 2 3 4 5 6; do
        sleep 0.5
        if poner_en_fondo; then PUESTO=si; break; fi
    done
fi
pkill -x swaybg || true
if [ "$PUESTO" = no ]; then
    # Respaldo: swaybg (solo imágenes; para vídeo/GIF muestra el fotograma)
    setsid swaybg -i "$FIJA" -m fill >/dev/null 2>&1 &
fi

# 2) Colores con matugen
matugen image "$FIJA" --source-color-index 0 -t scheme-fidelity

# Apps GTK y Qt/KDE: gsettings, kdeglobals y aviso para que se repinten
"$HOME/.local/bin/aplicar-colores-apps.sh" || true

pkill -SIGUSR2 waybar || true

# 3) Fondo de la pantalla de inicio de sesión (SDDM)
# Nítido y a tamaño de pantalla: el difuminado lo hace Tarjeta.qml igual que la pantalla de bloqueo
# (poco en el fondo, mucho detrás de la tarjeta). Antes: -resize 480x270 -blur 0x8 (muy borroso).
magick "$FIJA" -resize 1920x1080^ -gravity center -extent 1920x1080 -quality 92 /usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/fondo-actual.jpg
