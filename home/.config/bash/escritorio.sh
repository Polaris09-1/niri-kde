# ~/.config/bash/escritorio.sh — prompt (starship) y fastfetch del escritorio. Lo carga ~/.bashrc.
# Colores: los generan las plantillas de matugen (starship.toml y fastfetch/config.jsonc).
[[ $- == *i* ]] || return 0
# Dentro de Claude Code no se toca nada (ni prompt ni fastfetch)
[[ -n $CLAUDECODE ]] && return 0

# Prompt de píldoras con los colores del fondo. Sin starship se queda el PS1 de ~/.bashrc.
if command -v starship >/dev/null 2>&1 && [[ $TERM != dumb ]]; then
    eval "$(starship init bash)"
fi

# fastfetch solo en la PRIMERA terminal de la sesión gráfica (luego, escribiendo `fastfetch`).
# La marca vive en $XDG_RUNTIME_DIR (se borra al cerrar sesión) y lleva el socket de niri,
# que es distinto en cada inicio de niri. Nunca por SSH, en VS Code ni sin terminal de verdad.
_escritorio_fastfetch() {
    [[ -t 1 && -n $WAYLAND_DISPLAY && -z $SSH_CONNECTION && $TERM_PROGRAM != vscode ]] || return 0
    command -v fastfetch >/dev/null 2>&1 || return 0
    local id=${NIRI_SOCKET##*/}
    local marca="${XDG_RUNTIME_DIR:-/tmp}/fastfetch-mostrado-${id:-${XDG_SESSION_ID:-0}}"
    # set -C: crear la marca es atómico (si se abren dos terminales a la vez, solo una lo muestra)
    ( set -C; : > "$marca" ) 2>/dev/null || return 0
    fastfetch
}
_escritorio_fastfetch
unset -f _escritorio_fastfetch
