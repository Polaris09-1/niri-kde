#!/usr/bin/env bash
# Arranca el módulo "fondo" de Quickshell con decodificación de vídeo por hardware (VA-API)
# en la Radeon. Si la Radeon no es el primer nodo de render (aquí renderD128 = NVIDIA/nouveau),
# carga redirigir-render.so para que FFmpeg abra la Radeon en su lugar.
# Uso: fondo-arrancar.sh            (lo llama niri al iniciar sesión)
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
exec quickshell -c fondo
