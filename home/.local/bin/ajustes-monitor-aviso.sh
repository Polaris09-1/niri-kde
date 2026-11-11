#!/usr/bin/env bash
# ajustes-monitor-aviso.sh <título> <texto> — aviso al conectar o desconectar un monitor; "Configurar" abre Ajustes → Pantalla.
# Lo lanza "hola" con execDetached: espera la respuesta sin atar a la barra.
set -u
accion=$(notify-send -a "Pantalla" -i video-display -h string:x-hola-destino:ajustes:pantalla --action=configurar=Configurar --wait -- "$1" "$2" 2>/dev/null)
[ "$accion" = configurar ] && exec "$HOME/.local/bin/ajustes-abrir.sh" pantalla
exit 0
