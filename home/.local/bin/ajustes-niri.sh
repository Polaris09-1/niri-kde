#!/usr/bin/env bash
# ajustes-niri.sh — aplica un ajustes.kdl nuevo (lo recibe por stdin) solo si niri lo acepta.
# Copia la config a una carpeta temporal, valida ahí y, si pasa, respalda el actual y lo cambia de golpe.
# Si falla no toca nada, escribe el error por stdout y sale con 1.
set -u

C="$HOME/.config/niri"
T=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/ajustes-niri.XXXXXX") || { echo "No se pudo crear la carpeta temporal"; exit 1; }
trap 'rm -rf "$T"' EXIT

cat > "$T/ajustes.kdl"

# niri no comprueba que la distribución exista: con una mala, el teclado podría quedar en otra
capas=$(sed -n 's/^ *layout "\(.*\)"$/\1/p' "$T/ajustes.kdl")
if [ -n "$capas" ] && [ -r /usr/share/X11/xkb/rules/base.lst ]; then
    IFS=',' read -ra lista <<< "$capas"
    for l in "${lista[@]}"; do
        l=${l%%(*}
        if ! sed -n '/^! layout/,/^! variant/p' /usr/share/X11/xkb/rules/base.lst | awk '{print $1}' | grep -qxF -- "$l"; then
            echo "La distribución «$l» no existe"
            exit 1
        fi
    done
fi

for f in "$C"/*.kdl; do
    [ "$(basename "$f")" = ajustes.kdl ] || cp -p "$f" "$T/"
done

if ! salida=$(niri validate -c "$T/config.kdl" 2>&1); then
    # El mensaje útil es el último "×"; el resto es el dibujo del error para la terminal
    limpio=$(printf '%s\n' "$salida" | sed 's/\x1b\[[0-9;]*m//g')
    motivo=$(printf '%s\n' "$limpio" | sed -n 's/^.*× *//p' | tail -1)
    lugar=$(printf '%s\n' "$limpio" | sed -n 's/^ *╭─\[\(.*\)\]$/\1/p' | tail -1)
    echo "${motivo:-$(printf '%s\n' "$limpio" | grep -vE 'DEBUG|INFO' | head -6)}${lugar:+ ($lugar)}"
    exit 1
fi

[ -f "$C/ajustes.kdl" ] && "$HOME/.local/bin/ajustes-respaldo.sh" "$C/ajustes.kdl"
mv -f "$T/ajustes.kdl" "$C/ajustes.kdl"
