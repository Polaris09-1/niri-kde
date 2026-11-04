#!/usr/bin/env bash
# ajustes-pantalla.sh — prueba cambios de pantalla sin guardarlos, con vuelta atrás automática.
#   probar @ <salida> <args…> [@ <salida> <args…>…] -- @ <salida> <args para volver…> […]
#       aplica con `niri msg output`; si uno falla, deshace los ya hechos. Deja un vigilante.
#   conservar       cancela el vigilante (la app lo guarda en ajustes.kdl)
#   revertir @ <salida> <args para volver…> […]    vuelve ya
# El vigilante es un proceso aparte: si la app se cierra o se cuelga con la pantalla mal, revierte igual.
set -u
F="${XDG_RUNTIME_DIR:-/tmp}/ajustes-pantalla.pendiente"
ESPERA=17

# aplicar @ salida args… @ salida args…  → sale con 1 en el primer fallo y deja en HECHOS cuántos pasaron
aplicar() {
    HECHOS=0
    local actual=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "@" ] && [ ${#actual[@]} -gt 0 ]; then
            niri msg output "${actual[@]}" 2>&1 || return 1
            HECHOS=$((HECHOS + 1))
            actual=()
        elif [ "$1" != "@" ]; then
            actual+=("$1")
        fi
        shift
    done
    if [ ${#actual[@]} -gt 0 ]; then
        niri msg output "${actual[@]}" 2>&1 || return 1
        HECHOS=$((HECHOS + 1))
    fi
}

case "${1:-}" in
    probar)
        shift
        nuevo=()
        while [ $# -gt 0 ] && [ "$1" != "--" ]; do nuevo+=("$1"); shift; done
        shift
        volver=("$@")
        if ! error=$(aplicar "${nuevo[@]}"); then
            # Algo no se aplicó: todo vuelve como estaba (volver es la lista completa; repetir lo no aplicado es inocuo)
            aplicar "${volver[@]}" >/dev/null 2>&1
            printf '%s\n' "$error" | sed 's/\x1b\[[0-9;]*m//g' | head -3
            exit 1
        fi
        id="$$-$(date +%s%N)"
        echo "$id" > "$F"
        setsid bash -c '
            sleep "$1"
            if [ "$(cat "$2" 2>/dev/null)" = "$3" ]; then
                rm -f "$2"
                shift 3
                actual=()
                for a in "$@"; do
                    if [ "$a" = "@" ]; then
                        [ ${#actual[@]} -gt 0 ] && niri msg output "${actual[@]}"
                        actual=()
                    else
                        actual+=("$a")
                    fi
                done
                [ ${#actual[@]} -gt 0 ] && niri msg output "${actual[@]}"
            fi' _ "$ESPERA" "$F" "$id" "${volver[@]}" >/dev/null 2>&1 < /dev/null &
        ;;
    conservar)
        rm -f "$F"
        ;;
    revertir)
        shift
        rm -f "$F"
        aplicar "$@"
        ;;
    *)
        echo "uso: ajustes-pantalla.sh probar|conservar|revertir" >&2
        exit 2
        ;;
esac
