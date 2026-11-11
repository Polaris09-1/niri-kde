#!/usr/bin/env bash
# grabar.sh — graba la pantalla fuera de hola: una recarga de Quickshell mata a sus procesos hijos
# y un mp4 cortado así no se abre ("moov atom not found"). Lo lanza hola/Grabadora.qml con execDetached.
#
#   grabar.sh iniciar <id> [opciones de wf-recorder]   se queda vigilando hasta terminar de convertir
#   grabar.sh detener                                  SIGINT y espera a que se cierre el archivo
#   grabar.sh revisar                                  limpia el estado si el vigilante ya no existe
#
# Graba en .mkv (si algo lo corta, conserva lo ya escrito) y al terminar lo convierte a .mp4 para
# WhatsApp: H.264, yuv420p, 30 fps constantes, AAC y faststart. El .mkv se borra solo si el .mp4 está
# bien. El estado para hola va en $XDG_RUNTIME_DIR/grabacion/estado.json.
set -u

CARPETA="$HOME/Videos/Grabaciones"
DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/grabacion"
ESTADO="$DIR/estado.json"
CERROJO="$DIR/cerrojo"          # lo retiene el vigilante mientras vive
PIDWF="$DIR/wf-recorder.pid"
REGISTRO="$DIR/registro.log"
ESPERA_CIERRE=10                # segundos que detener espera a wf-recorder

mkdir -p "$DIR"

# escribir <estado> <id> <inicio> <ruta> <error>; de golpe, para que hola nunca lea medio archivo
escribir() {
    local t="$ESTADO.$$"
    printf '{"estado":"%s","id":"%s","inicio":%s,"ruta":"%s","error":"%s"}\n' "$1" "$2" "$3" "$4" "$5" >"$t" \
        && mv -f "$t" "$ESTADO"
}

avisar() { notify-send -a "Grabación" -i media-record "$@" 2>/dev/null; }

corto() { printf '%s' "${1/#$HOME/\~}"; }

vigilante_vivo() { ! ( flock -n 9 ) 9>"$CERROJO"; }

# PID de wf-recorder, solo si sigue siendo él
pid_wf() {
    local p
    p=$(cat "$PIDWF" 2>/dev/null) || return 1
    [ -n "$p" ] && [ "$(cat "/proc/$p/comm" 2>/dev/null)" = "wf-recorder" ] && printf '%s' "$p"
}

tiene_video() {
    [ -n "$(ffprobe -v error -select_streams v -read_intervals '%+#1' \
        -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null)" ]
}

mp4_correcto() {
    [ "$(ffprobe -v error -select_streams v -show_entries stream=codec_name,pix_fmt -of csv=p=0 "$1" 2>/dev/null)" = "h264,yuv420p" ]
}

# Comprueba la fuente de audio pedida antes de grabar: wf-recorder no falla con una inexistente,
# graba sin sonido sin decir nada. Escribe el motivo y devuelve 1 si no vale.
audio_valido() {
    local arg pedida="" hay=0 lista
    for arg in "$@"; do
        case "$arg" in
            --audio) hay=1 ;;
            --audio=*) hay=1; pedida="${arg#--audio=}" ;;
        esac
    done
    [ "$hay" = 1 ] || return 0
    lista=$(pactl list short sources 2>/dev/null | cut -f2)
    if [ -z "$lista" ]; then
        echo "No se pudo consultar el audio (PipeWire no responde)"; return 1
    fi
    if [ -n "$pedida" ]; then
        grep -qxF -- "$pedida" <<<"$lista" && return 0
        echo "No se encontró la salida de audio para grabar el sonido del sistema"; return 1
    fi
    # --audio a secas = fuente predeterminada: tiene que ser un micrófono, no el monitor de una salida
    pedida=$(pactl get-default-source 2>/dev/null)
    if [ -n "$pedida" ] && [ "${pedida%.monitor}" = "$pedida" ] && grep -qxF -- "$pedida" <<<"$lista"; then
        return 0
    fi
    echo "No hay ningún micrófono disponible"; return 1
}

iniciar() {
    local id="$1"; shift
    exec 9>"$CERROJO"
    flock -n 9 || exit 1    # ya hay una grabación o una conversión en curso

    mkdir -p "$CARPETA"
    local nombre mkv mp4 tmp inicio
    nombre="Grabación $(date '+%Y-%m-%d %H-%M-%S')"
    mkv="$CARPETA/$nombre.mkv"
    mp4="$CARPETA/$nombre.mp4"
    tmp="$CARPETA/.$nombre.parcial.mp4"
    inicio=$(date +%s)

    local motivo
    if ! motivo=$(audio_valido "$@"); then
        escribir inactivo "$id" "$inicio" "" "$motivo"
        avisar -u critical "No se empezó a grabar" "$motivo"
        exit 1
    fi

    : >"$REGISTRO"
    wf-recorder -y -f "$mkv" "$@" >>"$REGISTRO" 2>&1 9>&- &
    local wf=$!
    printf '%s' "$wf" >"$PIDWF"
    escribir grabando "$id" "$inicio" "$mp4" ""

    # Apagar o cerrar la sesión: cerrar el .mkv y salir, sin ponerse a convertir
    local saliendo=0
    trap 'saliendo=1; kill -INT "$wf" 2>/dev/null' TERM INT
    trap '' HUP
    while kill -0 "$wf" 2>/dev/null; do wait "$wf"; done
    rm -f "$PIDWF"

    if [ "$saliendo" = 1 ]; then
        escribir inactivo "$id" "$inicio" "$mp4" ""
        exit 0
    fi

    if ! tiene_video "$mkv"; then
        rm -f "$mkv"
        local motivo="No se pudo iniciar la grabación"
        grep -qiE 'audio|pulse|pipewire' "$REGISTRO" && motivo="No se pudo grabar el audio elegido"
        escribir inactivo "$id" "$inicio" "$mp4" "$motivo"
        exit 1
    fi

    local dur=$(( $(date +%s) - inicio ))
    escribir procesando "$id" "$inicio" "$mp4" ""

    if nice -n 10 ffmpeg -nostdin -v error -y -i "$mkv" \
            -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2:out_range=tv,format=yuv420p' -fps_mode cfr -r 30 \
            -c:v libx264 -preset veryfast -crf 23 -profile:v high \
            -c:a aac -b:a 160k -movflags +faststart -f mp4 "$tmp" >>"$REGISTRO" 2>&1 9>&- \
        && mp4_correcto "$tmp" && mv -n "$tmp" "$mp4" && [ ! -e "$tmp" ]; then
        rm -f "$mkv"
        escribir inactivo "$id" "$inicio" "$mp4" ""
        avisar -h "string:x-hola-destino:video:$mp4" \
            "Grabación guardada ($(printf '%02d:%02d' $((dur / 60)) $((dur % 60))))" "$(corto "$mp4")"
    else
        rm -f "$tmp"
        escribir inactivo "$id" "$inicio" "$mp4" "No se pudo convertir: el vídeo sigue en el .mkv"
        avisar -u critical -h "string:x-hola-destino:carpeta:$mkv" \
            "No se pudo convertir la grabación" "El vídeo sigue en $(corto "$mkv")"
    fi
}

detener() {
    if ! vigilante_vivo; then revisar; return; fi
    local p
    p=$(pid_wf) || return 0     # ya está convirtiendo: no hay nada que detener
    kill -INT "$p" 2>/dev/null
    local i
    for (( i = 0; i < ESPERA_CIERRE * 10; i++ )); do
        [ -d "/proc/$p" ] || return 0
        sleep 0.1
    done
    avisar -u critical "La grabación no termina de cerrarse" "Lo escrito hasta ahora sigue en el .mkv de ~/Videos/Grabaciones"
}

# El vigilante murió de golpe: el estado se quedaría en "grabando" para siempre
revisar() {
    vigilante_vivo && return 0
    [ -r "$ESTADO" ] || return 0
    grep -q '"estado":"inactivo"' "$ESTADO" && return 0
    local p
    p=$(pid_wf) && kill -INT "$p" 2>/dev/null
    rm -f "$PIDWF"
    escribir inactivo "" 0 "" "La grabación se interrumpió; lo grabado sigue en el .mkv"
}

case "${1:-}" in
    iniciar) shift; [ $# -ge 1 ] || exit 2; iniciar "$@" ;;
    detener) detener ;;
    revisar) revisar ;;
    *) echo "uso: grabar.sh iniciar <id> [opciones] | detener | revisar" >&2; exit 2 ;;
esac
