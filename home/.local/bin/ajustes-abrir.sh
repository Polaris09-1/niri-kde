#!/usr/bin/env bash
# ajustes-abrir.sh [sección] — abre la app de Ajustes o, si ya está abierta, la trae al frente.
# Solo corre mientras la ventana está abierta: cerrada no gasta memoria.
set -u
seccion=${1:-}

if qs -c ajustes ipc call ajustes abrir "$seccion" >/dev/null 2>&1; then
    id=$(niri msg -j windows | jq -r 'first(.[] | select(.title == "Ajustes") | .id) // empty')
    [ -n "$id" ] && niri msg action focus-window --id "$id"
    exit 0
fi
# Sin la barra de título de Qt: la ventana lleva la suya
AJUSTES_SECCION="$seccion" QT_WAYLAND_DISABLE_WINDOWDECORATION=1 exec qs -c ajustes --no-duplicate
