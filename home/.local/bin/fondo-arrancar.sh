#!/usr/bin/env bash
# Arranca el módulo "fondo" de Quickshell con decodificación de vídeo por hardware (VA-API)
# en la Radeon. Si la Radeon no es el primer nodo de render (aquí renderD128 = NVIDIA/nouveau),
# carga redirigir-render.so para que FFmpeg abra la Radeon en su lugar.
# Uso: fondo-arrancar.sh [módulo]   (lo llama niri al iniciar sesión; módulo = fondo por defecto)
#      fondo-arrancar.sh galeria   → la galería, para su vista previa de vídeo (la lanza galeria-abrir.sh)
#      pkill -f -- '-c fondo$'; setsid ~/.local/bin/fondo-arrancar.sh &   (reiniciarlo a mano)
SO="$HOME/.local/lib/fondo/redirigir-render.so"
primero="" ; amd=""
for n in /dev/dri/renderD*; do
    [ -e "$n" ] || continue
    [ -z "$primero" ] && primero="$n"
    drv="$(basename "$(readlink -f "/sys/class/drm/$(basename "$n")/device/driver")")"
    [ "$drv" = amdgpu ] && [ -z "$amd" ] && amd="$n"
done
export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
export LIBVA_DRIVER_NAME=radeonsi
if [ -n "$amd" ] && [ "$amd" != "$primero" ] && [ -f "$SO" ]; then
    export FONDO_RENDER_DESDE="$primero" FONDO_RENDER_HASTA="$amd"
    export LD_PRELOAD="$SO${LD_PRELOAD:+:$LD_PRELOAD}"
fi
MODULO="${1:-fondo}"
case "$MODULO" in fondo|galeria) ;; *) echo "módulo no previsto: $MODULO" >&2; exit 2 ;; esac
# La galería se lanza al pulsar el atajo: dos pulsaciones seguidas no deben crear dos
if [ "$MODULO" = galeria ]; then exec quickshell -c galeria --no-duplicate; fi
exec quickshell -c "$MODULO"
