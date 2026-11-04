#!/usr/bin/env bash
# fondo-login.sh <archivo elegido> <imagen fija>
# Pone el fondo en la pantalla de inicio de sesión (tema SDDM). Lo lanza wallpaper.sh en su propia
# sesión (setsid) y con systemd-inhibit: así no muere si la galería se recarga por matugen y el
# apagado espera (hasta 5 s) a que termine.
# - Solo escribe si el archivo sigue siendo el fondo elegido: si cambias dos veces seguidas, gana el último.
# - Escrituras atómicas (temporal + mv) y sync: un corte no deja un archivo a medias.
# - El vídeo o GIF del fondo anterior se quita enseguida: mientras se convierte uno nuevo, el login
#   muestra la imagen fija nueva, nunca el vídeo viejo.
# Registro: $XDG_RUNTIME_DIR/fondo-login.log
set -u
ARCH="$1"
FIJA="$2"
BG=/usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds
GUARDADO="$HOME/.cache/wallpaper-actual"
MARCA="$BG/.fondo-actual.origen"    # de qué fondo salió el vídeo o GIF que hay ahora
RUN="${XDG_RUNTIME_DIR:-/tmp}"
LOG="$RUN/fondo-login.log"
CERROJO="$RUN/fondo-login.lock"

registro() { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG"; }
vigente() { [ "$(cat "$GUARDADO" 2>/dev/null)" = "$ARCH" ]; }

# Copia atómica: no toca nada si el destino ya es igual
copiar() {
    cmp -s "$1" "$2" && return 0
    cp -f "$1" "$2.tmp" && mv -f "$2.tmp" "$2"
}

# ----- Parte rápida: imagen fija y limpieza del vídeo anterior -----
(
    flock 8
    vigente || { registro "omitido (ya no es el actual): $ARCH"; exit 1; }
    TMP="$BG/.fondo-actual.tmp.jpg"
    if ! magick "$FIJA" -resize 1920x1080^ -gravity center -extent 1920x1080 -quality 92 "$TMP"; then
        rm -f "$TMP"; registro "FALLO magick: $FIJA"; exit 1
    fi
    mv -f "$TMP" "$BG/fondo-actual.jpg"
    if [ "$(cat "$MARCA" 2>/dev/null)" != "$ARCH" ]; then
        rm -f "$BG/fondo-actual.mp4" "$BG/fondo-actual.gif"
    fi
    printf '%s\n' "$ARCH" > "$MARCA"
    case "${ARCH,,}" in
        *.gif) copiar "$ARCH" "$BG/fondo-actual.gif" ;;
    esac
    sync -f "$BG"
    registro "imagen lista: $ARCH"
) 8>"$CERROJO" || exit 0

# ----- Parte lenta: copia optimizada del vídeo (sin cerrojo: la conversión puede tardar) -----
case "${ARCH,,}" in
    *.mp4|*.webm|*.mkv|*.mov) ;;
    *) exit 0 ;;
esac
OPT="$("$HOME/.local/bin/fondo-optimizar.sh" "$ARCH" 1920 1080 30 | sed -n 's/^LISTO //p' | tail -n1)"
[ -n "$OPT" ] || OPT="$ARCH"
(
    flock 8
    vigente || { registro "vídeo omitido (ya no es el actual): $ARCH"; exit 0; }
    if copiar "$OPT" "$BG/fondo-actual.mp4"; then
        sync -f "$BG"
        registro "vídeo listo: $ARCH"
    else
        rm -f "$BG/fondo-actual.mp4.tmp"; registro "FALLO copia de vídeo: $ARCH"
    fi
) 8>"$CERROJO"
