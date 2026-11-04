#!/usr/bin/env bash
# espejo.sh — reflejar un monitor en otro (M4). niri no tiene espejo: lo dibuja el módulo `espejo` de Quickshell.
#   espejo.sh iniciar <origen> <destino>   empieza y lo recuerda
#   espejo.sh parar                        termina y lo olvida
#   espejo.sh reanudar                     si hay un modo recordado y sus dos monitores están encendidos, empieza
#                                          (lo llama `hola` al arrancar y cada vez que cambian las pantallas)
#   espejo.sh info
#   espejo.sh poner <origen> <destino> | poner -    deja ese estado, venga de donde venga (- = sin espejo)
#   espejo.sh probar iniciar <origen> <destino> | probar parar
#       lo aplica y, si nadie dice "conservar" en 17 s, vuelve solo, aunque Ajustes se cierre. Errores por stdout.
#   espejo.sh conservar | revertir                  responde a una prueba
#
# Mientras dura:
#   $XDG_RUNTIME_DIR/espejo-activo.json    origen, destino y dónde estaba cada monitor. Lo lee Principal.qml, y con él
#                                          barra, dock y fondo dejan de dibujarse en el destino.
#   ~/.local/state/espejo/modo.json        qué recordar, por identidad del monitor (no sube al repo).
#
# El módulo corre dentro de este script (_vigilar): si se cae o se apaga solo, aquí se devuelve todo a su sitio.
#
# Colocación: el destino va en diagonal y lejos de todos, sin ningún eje en común. Ojo, medido en niri 26.04:
# con `position set` en un solo monitor, niri recoloca a su derecha los que no tienen posición explícita (el cursor se
# queda atrás y parece que salta). Por eso primero se fijan todos en su sitio. Un `position` también sobrevive a
# desconectar el monitor: al terminar se quita aunque ya no esté.
set -u

RUN=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
ACTIVO=$RUN/espejo-activo.json
CERROJO=$RUN/espejo.cerrojo
ARRANQUE=$RUN/espejo-arranque.cerrojo
REGISTRO=$RUN/espejo.log
MODO=${XDG_STATE_HOME:-$HOME/.local/state}/espejo/modo.json
PENDIENTE=$RUN/espejo.pendiente
SEPARACION=2000
ESPERA=17

salidas() { niri msg -j outputs; }

# ¿Corre ya? El cerrojo lo tiene _vigilar mientras vive
corriendo() {
    [ -e "$CERROJO" ] || return 1
    ! flock -n "$CERROJO" true
}

# Mismo criterio que Ajustes: "marca modelo serie"; sin marca ni modelo, el conector
identidad() {
    salidas | jq -r --arg s "$1" '.[$s] | if . == null then empty else
        ([.make, .model] | map(select(. != null and . != "Unknown")) | join(" ")) as $n
        | if $n == "" then $s else $n + " " + (.serial // "Unknown") end end'
}

conector_de() {
    local id=$1 s
    for s in $(salidas | jq -r 'keys[]'); do
        [ "$(identidad "$s")" = "$id" ] && { echo "$s"; return 0; }
    done
    return 1
}

encendida() { salidas | jq -e --arg s "$1" '.[$s].logical != null' >/dev/null; }

posiciones() { salidas | jq -c 'with_entries(select(.value.logical) | .value = (.value.logical | {x, y}))'; }

# Deja los monitores donde estaban y el cursor en el origen. Sirve también para un estado que quedó de una caída.
restaurar() {
    [ -f "$ACTIVO" ] || return 0
    local origen destino guardadas s
    origen=$(jq -r .origen "$ACTIVO"); destino=$(jq -r .destino "$ACTIVO")
    guardadas=$(jq -c .posiciones "$ACTIVO")
    rm -f "$ACTIVO"
    # Primero automático: es lo normal, y deja a niri colocar los monitores sin posición guardada
    for s in $(jq -r 'keys[]' <<<"$guardadas"); do niri msg output "$s" position auto >/dev/null 2>&1; done
    sleep 0.3
    # Si no quedaron donde estaban (posiciones elegidas en Ajustes), todos explícitos; los que falten no cuentan
    if ! jq -en --argjson g "$guardadas" --argjson a "$(posiciones)" \
        '$g | to_entries | all($a[.key] == null or $a[.key] == .value)' >/dev/null; then
        for s in $(jq -r --arg d "$destino" 'keys | map(select(. != $d)) + [$d] | .[]' <<<"$guardadas"); do
            encendida "$s" && niri msg output "$s" position set \
                "$(jq -r --arg s "$s" '.[$s].x' <<<"$guardadas")" "$(jq -r --arg s "$s" '.[$s].y' <<<"$guardadas")"
        done
    fi
    encendida "$origen" && niri msg action focus-monitor "$origen"
    return 0
}

# empezar <origen> <destino>: ya validados; escribe el estado, coloca los monitores y deja el módulo corriendo aparte
empezar() {
    local origen=$1 destino=$2 antes s nx ny
    antes=$(posiciones)
    jq -n --arg o "$origen" --arg d "$destino" --argjson p "$antes" \
        '{origen: $o, destino: $d, posiciones: $p}' > "$ACTIVO.nuevo"
    mv -f "$ACTIVO.nuevo" "$ACTIVO"
    for s in $(jq -r --arg d "$destino" 'keys | map(select(. != $d)) | .[]' <<<"$antes"); do
        niri msg output "$s" position set \
            "$(jq -r --arg s "$s" '.[$s].x' <<<"$antes")" "$(jq -r --arg s "$s" '.[$s].y' <<<"$antes")"
    done
    # Más allá de todos los demás, en los dos ejes
    read -r nx ny < <(salidas | jq -r --arg d "$destino" --argjson s "$SEPARACION" '
        [to_entries[] | select(.key != $d and .value.logical) | .value.logical]
        | "\(map(.x + .width) | max + $s) \(map(.y + .height) | max + $s)"')
    niri msg output "$destino" position set "$nx" "$ny"
    niri msg action focus-monitor "$origen"
    setsid -f "$0" _vigilar </dev/null >>"$REGISTRO" 2>&1
}

# Lo que hay ahora: {origen, destino}, o null sin espejo
estado_actual() {
    if corriendo && [ -f "$ACTIVO" ]; then jq -c '{origen, destino}' "$ACTIVO"; else echo null; fi
}

case "${1:-}" in
    poner)
        [ $# -ge 2 ] || { echo "uso: espejo.sh poner <origen> <destino> | poner -" >&2; exit 2; }
        "$0" parar || exit 1
        [ "$2" = "-" ] && exit 0
        exec "$0" iniciar "$2" "$3"
        ;;
    probar)
        shift
        antes=$(estado_actual)
        case "${1:-}" in
            iniciar) [ $# -eq 3 ] || { echo "Faltan los monitores."; exit 2; }; nuevo=("$2" "$3") ;;
            parar) nuevo=("-") ;;
            *) echo "uso: espejo.sh probar iniciar <origen> <destino> | probar parar"; exit 2 ;;
        esac
        if ! error=$("$0" poner "${nuevo[@]}" 2>&1); then
            # Volver a como estaba: un fallo no puede dejarlo a medias
            if [ "$antes" = null ]; then "$0" poner - >/dev/null 2>&1
            else "$0" poner "$(jq -r .origen <<<"$antes")" "$(jq -r .destino <<<"$antes")" >/dev/null 2>&1; fi
            echo "$error" | head -3
            exit 1
        fi
        id="$$-$(date +%s%N)"
        jq -n --arg id "$id" --argjson a "$antes" '{id: $id, antes: $a}' > "$PENDIENTE"
        setsid -f bash -c '
            sleep "$1"
            [ "$(jq -r .id "$2" 2>/dev/null)" = "$3" ] && exec "$4" revertir' _ "$ESPERA" "$PENDIENTE" "$id" "$0" \
            </dev/null >>"$REGISTRO" 2>&1
        ;;
    conservar)
        rm -f "$PENDIENTE"
        ;;
    revertir)
        [ -f "$PENDIENTE" ] || exit 0
        antes=$(jq -c .antes "$PENDIENTE")
        rm -f "$PENDIENTE"
        if [ "$antes" = null ]; then exec "$0" poner -; fi
        exec "$0" poner "$(jq -r .origen <<<"$antes")" "$(jq -r .destino <<<"$antes")"
        ;;
    iniciar)
        [ $# -eq 3 ] || { echo "uso: espejo.sh iniciar <origen> <destino>" >&2; exit 2; }
        origen=$2; destino=$3
        [ "$origen" != "$destino" ] || { echo "El origen y el destino son el mismo monitor." >&2; exit 1; }
        encendida "$origen" || { echo "$origen no está encendido." >&2; exit 1; }
        encendida "$destino" || { echo "$destino no está encendido." >&2; exit 1; }
        exec 8>"$ARRANQUE"; flock -n 8 || { echo "Ya se está iniciando." >&2; exit 1; }
        corriendo && { echo "El espejo ya está activo: páralo antes." >&2; exit 1; }
        restaurar
        mkdir -p "$(dirname "$MODO")"
        jq -n --arg o "$(identidad "$origen")" --arg d "$(identidad "$destino")" \
            '{origen: $o, destino: $d}' > "$MODO.nuevo" && mv -f "$MODO.nuevo" "$MODO"
        empezar "$origen" "$destino"
        ;;
    parar)
        rm -f "$MODO"
        if corriendo; then
            qs -c espejo ipc call espejo parar >/dev/null 2>&1
            for _ in $(seq 1 30); do corriendo || break; sleep 0.1; done
            if corriendo; then echo "El módulo no se cerró." >&2; exit 1; fi
        else
            restaurar
        fi
        ;;
    reanudar)
        exec 8>"$ARRANQUE"; flock -n 8 || exit 0
        corriendo && exit 0
        restaurar   # un estado sin nadie que lo atienda es de una caída
        [ -f "$MODO" ] || exit 0
        origen=$(conector_de "$(jq -r .origen "$MODO")") || exit 0
        destino=$(conector_de "$(jq -r .destino "$MODO")") || exit 0
        [ "$origen" != "$destino" ] || exit 0
        encendida "$origen" && encendida "$destino" || exit 0
        empezar "$origen" "$destino"
        ;;
    info)
        a=false; corriendo && a=true
        jq -n --argjson activo "$a" \
            --argjson estado "$(cat "$ACTIVO" 2>/dev/null || echo null)" \
            --argjson recordado "$(cat "$MODO" 2>/dev/null || echo null)" \
            '{activo: $activo, estado: $estado, recordado: $recordado}'
        ;;
    _vigilar)
        exec 9>"$CERROJO"
        flock -n 9 || exit 0
        # El módulo no debe heredar el cerrojo de arranque: se liberaría tarde
        exec 8>&-
        trap 'kill "$hijo" 2>/dev/null' TERM INT
        qs -c espejo &
        hijo=$!
        while kill -0 "$hijo" 2>/dev/null; do wait "$hijo"; done
        restaurar
        ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
