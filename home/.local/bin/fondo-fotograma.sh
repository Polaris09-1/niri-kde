#!/usr/bin/env bash
# fondo-fotograma.sh <archivo>
# Imprime una imagen fija que represente el fondo:
#  - imagen normal  -> la misma ruta
#  - vídeo o GIF    -> un fotograma sacado con ffmpeg, guardado en
#                      ~/.cache/galeria/fotogramas/<md5 de la ruta>.jpg
# (la galería calcula el mismo nombre con Qt.md5, no cambiar el esquema)
set -euo pipefail
ARCH="$(realpath "$1")"
case "${ARCH,,}" in
    *.mp4|*.webm|*.mkv|*.mov|*.gif) ;;
    *) printf '%s\n' "$ARCH"; exit 0 ;;
esac

DIR="$HOME/.cache/galeria/fotogramas"
mkdir -p "$DIR"
SUMA="$(printf '%s' "$ARCH" | md5sum | cut -d' ' -f1)"
OUT="$DIR/$SUMA.jpg"

if [ ! -s "$OUT" ] || [ "$ARCH" -nt "$OUT" ]; then
    TMP="$DIR/.$SUMA.$$.jpg"
    # Fotograma al segundo 1; si el vídeo es más corto, el primero
    ffmpeg -nostdin -loglevel error -y -ss 1 -i "$ARCH" -frames:v 1 -q:v 2 "$TMP" 2>/dev/null || true
    [ -s "$TMP" ] || ffmpeg -nostdin -loglevel error -y -i "$ARCH" -frames:v 1 -q:v 2 "$TMP"
    mv -f "$TMP" "$OUT"
fi
printf '%s\n' "$OUT"
