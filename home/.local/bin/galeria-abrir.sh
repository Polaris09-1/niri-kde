#!/usr/bin/env bash
# galeria-abrir.sh — Mod+Shift+W. La galería solo corre mientras se usa: cerrada no gasta memoria.
# Si ya corre, abre o cierra; si no, la arranca (al arrancar se abre sola y al ocultarse termina).
# Una segunda pulsación mientras carga no crea otra: fondo-arrancar.sh la lanza con --no-duplicate.
set -u
qs -c galeria ipc call galeria toggle >/dev/null 2>&1 && exit 0
exec "$HOME/.local/bin/fondo-arrancar.sh" galeria
