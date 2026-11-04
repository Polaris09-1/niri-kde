#!/usr/bin/env bash
# workspace-circular.sh <arriba|abajo> — cambia de workspace dando la vuelta en el monitor enfocado.
# Ciclo: 1 → 2 → … → vacío del final → 1, y al revés (el vacío es una parada porque ahí está el escritorio).
# Si ese monitor no tiene ventanas en ningún workspace, no hace nada.
set -u

case "${1:-}" in
    abajo) paso=1 ;;
    arriba) paso=-1 ;;
    *) echo "uso: workspace-circular.sh <arriba|abajo>" >&2; exit 2 ;;
esac

espacios=$(niri msg -j workspaces) || exit 1
ventanas=$(niri msg -j windows) || exit 1

destino=$(jq -nr --argjson e "$espacios" --argjson v "$ventanas" --argjson paso "$paso" '
    ($e | map(select(.is_focused)) | first // empty) as $actual
    | ($e | map(select(.output == $actual.output)) | sort_by(.idx)) as $lista
    | ($lista | map(.id)) as $ids
    | select(any($v[]; .workspace_id as $w | $ids | index($w)))
    | ($ids | index($actual.id)) as $pos
    | $lista[($pos + $paso + ($lista | length)) % ($lista | length)].idx
') || exit 1

[ -n "$destino" ] && exec niri msg action focus-workspace "$destino"
exit 0
