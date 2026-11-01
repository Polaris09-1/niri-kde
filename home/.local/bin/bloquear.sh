#!/usr/bin/env bash
# Bloquea la sesión con el módulo Quickshell "bloqueo" (2026-11-01) y espera a que niri confirme
# el bloqueo ("seguro"), para que `swayidle -w before-sleep` no deje dormir al portátil con el
# escritorio a la vista. Si el módulo no responde, usa swaylock (-f: se queda en segundo plano).
if qs -c bloqueo ipc call bloqueo bloquear >/dev/null 2>&1; then
    for _ in $(seq 1 60); do
        [ "$(qs -c bloqueo ipc call bloqueo estado 2>/dev/null)" = seguro ] && exit 0
        sleep 0.05
    done
    exit 0
fi
exec swaylock -f
