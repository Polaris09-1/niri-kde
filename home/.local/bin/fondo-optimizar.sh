#!/usr/bin/env bash
# fondo-optimizar.sh <vídeo> <ancho> <alto> <fps>
# Crea (una sola vez) una copia del vídeo para usar de fondo: recortada y escalada al tamaño
# de la pantalla y limitada a <fps>, en H.264 (lo decodifica la Radeon por VA-API), sin audio.
# El original no se toca. Caché: ~/.cache/fondo/optimizados/<md5 ruta>-<ancho>x<alto>-<fps>.mp4
# Salida (una línea por evento, la lee el módulo "fondo"):
#   LISTO <ruta>      la copia ya existe (o se acaba de crear): usarla
#   ORIGINAL          no existe: usa el original mientras tanto (luego llega LISTO o FALLO)
#   FALLO <motivo>    no se pudo crear: seguir con el original
set -u
SRC="$1"; W="$2"; H="$3"; FPS="$4"
DIR="$HOME/.cache/fondo/optimizados"
mkdir -p "$DIR"
HASH="$(printf '%s' "$SRC" | md5sum | cut -d' ' -f1)"
DST="$DIR/$HASH-${W}x${H}-${FPS}.mp4"

# Al día si existe y es más nueva que el original
if [ -s "$DST" ] && [ "$DST" -nt "$SRC" ]; then echo "LISTO $DST"; exit 0; fi

# ¿Ya es pequeño? (≤ pantalla y ≤ fps) → no hace falta copia
read -r VW VH VR < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate \
    -of csv=p=0:s=' ' "$SRC" 2>/dev/null) || true
VFPS=$(awk -v r="${VR:-0/1}" 'BEGIN{split(r,a,"/"); print (a[2]>0 ? a[1]/a[2] : 0)}')
CODEC="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$SRC" 2>/dev/null)"
if [ -n "${VW:-}" ] && [ "$VW" -le "$W" ] && [ "$VH" -le "$H" ] \
   && awk -v v="$VFPS" -v f="$FPS" 'BEGIN{exit !(v <= f + 0.5)}' \
   && [[ "$CODEC" =~ ^(h264|hevc|vp9|av1)$ ]]; then
    echo "LISTO $SRC"; exit 0
fi

echo "ORIGINAL"
# Solo un proceso por destino
exec 9>"$DST.lock"
if ! flock -n 9; then flock 9; [ -s "$DST" ] && echo "LISTO $DST" || echo "FALLO otro proceso falló"; exit 0; fi

# Nodo de render de la Radeon (renderD128 es la NVIDIA)
RENDER=""
for n in /dev/dri/renderD*; do
    [ "$(basename "$(readlink -f "/sys/class/drm/$(basename "$n")/device/driver")")" = amdgpu ] && { RENDER="$n"; break; }
done

TMP="$DST.tmp.mp4"
FILTRO="fps=$FPS,scale=$W:$H:force_original_aspect_ratio=increase:flags=bicubic,crop=$W:$H,setsar=1"
ok=no
if [ -n "$RENDER" ]; then
    # Decodifica y codifica en la GPU; escalar/recortar en la CPU (una sola vez)
    nice -n 19 ffmpeg -nostdin -hide_banner -v error -y \
        -hwaccel vaapi -hwaccel_device "$RENDER" -hwaccel_output_format vaapi -i "$SRC" -an -sn -dn \
        -vf "hwdownload,format=nv12,$FILTRO,format=nv12,hwupload" -vaapi_device "$RENDER" \
        -c:v h264_vaapi -rc_mode CQP -qp 20 -g $((FPS * 2)) -movflags +faststart "$TMP" 2>"$DST.log" && ok=si
fi
if [ "$ok" = no ]; then
    # Respaldo por software
    nice -n 19 ffmpeg -nostdin -hide_banner -v error -y -i "$SRC" -an -sn -dn -vf "$FILTRO,format=yuv420p" \
        -c:v libx264 -preset veryfast -crf 20 -g $((FPS * 2)) -movflags +faststart "$TMP" 2>>"$DST.log" && ok=si
fi
if [ "$ok" = si ] && [ -s "$TMP" ]; then
    mv -f "$TMP" "$DST"; rm -f "$DST.log" "$DST.lock"; echo "LISTO $DST"
else
    rm -f "$TMP"; echo "FALLO ver $DST.log"
fi
