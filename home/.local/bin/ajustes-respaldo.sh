#!/usr/bin/env bash
# ajustes-respaldo.sh <archivo> — guarda una copia antes de que la app de Ajustes lo cambie.
# Conserva las 50 más recientes de cada archivo en ~/.local/state/ajustes/respaldos (no sube al repo).
set -u
archivo=${1:?falta el archivo}
[ -f "$archivo" ] || exit 0
D="${XDG_STATE_HOME:-$HOME/.local/state}/ajustes/respaldos"
mkdir -p "$D" || exit 1
base=$(basename "$archivo")
cp -p -- "$archivo" "$D/$(date +%Y%m%d-%H%M%S-%N)-$base" || exit 1
ls -1t "$D"/*-"$base" 2>/dev/null | tail -n +51 | while IFS= read -r viejo; do rm -f -- "$viejo"; done
