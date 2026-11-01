#!/usr/bin/env bash
# install.sh — instala el escritorio "niri-kde" (niri + Quickshell + matugen) en Arch Linux.
#
#   ./install.sh               instala paquetes, archivos y tema SDDM (pregunta antes de cada paso)
#   ./install.sh --simular     muestra lo que haría, sin cambiar nada
#   ./install.sh --sin-paquetes   no ejecuta pacman
#   ./install.sh --sin-sddm       no toca el tema de la pantalla de inicio de sesión
#   ./install.sh --si             no pregunta (responde "sí" a todo)
#
# Antes de sobrescribir cualquier archivo existente lo copia a
#   ~/respaldos-limpieza/<fecha>-niri-kde-install/   (con la misma ruta relativa a $HOME).
# Solo usa sudo para pacman y para /usr/share/sddm y /etc/sddm.conf.d.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
ORIGEN="$REPO/home"
FECHA="$(date +%F-%H%M%S)"
RESPALDO="$HOME/respaldos-limpieza/$FECHA-niri-kde-install"

SIMULAR=no; PAQUETES=si; SDDM=si; PREGUNTAR=si
for a in "$@"; do
    case "$a" in
        --simular) SIMULAR=si ;;
        --sin-paquetes) PAQUETES=no ;;
        --sin-sddm) SDDM=no ;;
        --si) PREGUNTAR=no ;;
        -h|--help|--ayuda) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opción desconocida: $a (usa --ayuda)"; exit 2 ;;
    esac
done

# ---------- utilidades ----------
azul() { printf '\033[1;34m%s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m%s\033[0m\n' "$*"; }
error() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }
hacer() {   # ejecuta un comando, o solo lo muestra con --simular
    if [ "$SIMULAR" = si ]; then printf '   [simular] %s\n' "$*"; else "$@"; fi
}
confirmar() {   # confirmar "pregunta" → 0 si sí
    [ "$PREGUNTAR" = no ] && return 0
    [ "$SIMULAR" = si ] && return 0
    local r; read -r -p "$1 [S/n] " r
    [[ -z "$r" || "$r" =~ ^[sSyY] ]]
}

[ "$EUID" -eq 0 ] && error "no lo ejecutes como root ni con sudo: el script pide sudo solo cuando hace falta."
command -v pacman >/dev/null || error "este instalador es para Arch Linux (no encuentro pacman)."
[ -d "$ORIGEN" ] || error "no encuentro $ORIGEN (¿ejecutas el script desde el repositorio?)."

# Nombre para el saludo del reloj: el nombre completo del usuario, o el usuario con mayúscula
NOMBRE="$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1 | awk '{print $1}')"
[ -n "$NOMBRE" ] || NOMBRE="$(printf '%s' "${USER^}")"

[ "$SIMULAR" = si ] && aviso "Modo simulación: no se cambia nada."
echo "Repositorio: $REPO"
echo "Respaldo de lo que se sobrescriba: $RESPALDO"
echo

# ---------- 1) Paquetes ----------
if [ "$PAQUETES" = si ]; then
    azul "1) Paquetes (repos oficiales, pacman --needed)"
    mapfile -t LISTA < <(sed 's/#.*//' "$REPO/paquetes.txt" | tr ' ' '\n' | grep -v '^\s*$')
    echo "   ${#LISTA[@]} paquetes: ${LISTA[*]}"
    if confirmar "   ¿Instalar con sudo pacman -S --needed?"; then
        hacer sudo pacman -S --needed "${LISTA[@]}"
    else
        aviso "   Paquetes omitidos."
    fi
else
    azul "1) Paquetes: omitidos (--sin-paquetes)"
fi
echo

# ---------- 2) Archivos ----------
azul "2) Archivos de configuración en $HOME"
nuevos=0; iguales=0; respaldados=0
# Cambia los marcadores del repositorio por los datos de este usuario (solo archivos de texto)
personalizar() {
    if grep -qI . "$1" 2>/dev/null; then
        sed -i -e "s#@HOME@#$HOME#g" -e "s#@NOMBRE@#$NOMBRE#g" "$1"
    fi
}
instalar_uno() {   # instalar_uno <ruta relativa a ORIGEN>
    local rel="$1" src="$ORIGEN/$1" dst="$HOME/$1" tmp
    tmp="$(mktemp)"
    if [ -L "$src" ]; then
        # Enlace simbólico (Colors.qml → ../hola/Colors.qml): se recrea tal cual
        # (igual si ya apunta al mismo archivo, aunque el enlace sea absoluto)
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(realpath -m "$(dirname "$dst")/$(readlink "$src")")" ]; then
            iguales=$((iguales+1)); rm -f "$tmp"; return
        fi
    else
        cp -p "$src" "$tmp"; personalizar "$tmp"
        if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$tmp" "$dst"; then iguales=$((iguales+1)); rm -f "$tmp"; return; fi
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        hacer mkdir -p "$(dirname "$RESPALDO/$rel")"
        hacer cp -a "$dst" "$RESPALDO/$rel"
        respaldados=$((respaldados+1))
    fi
    hacer mkdir -p "$(dirname "$dst")"
    if [ -L "$src" ]; then
        hacer rm -f "$dst"
        hacer ln -s "$(readlink "$src")" "$dst"
    else
        [ -L "$dst" ] && hacer rm -f "$dst"
        hacer cp -p "$tmp" "$dst"
    fi
    rm -f "$tmp"
    nuevos=$((nuevos+1))
    [ "$SIMULAR" = si ] && echo "   → $rel"
    return 0
}
if confirmar "   ¿Copiar los archivos (con respaldo de los que ya existan)?"; then
    while IFS= read -r ruta; do
        [ -e "$ORIGEN/$ruta" ] || [ -L "$ORIGEN/$ruta" ] || { aviso "   falta en el repositorio: $ruta"; continue; }
        while IFS= read -r -d '' f; do
            instalar_uno "${f#"$ORIGEN"/}"
        done < <(find "$ORIGEN/$ruta" \( -type f -o -type l \) -print0)
    done < <(grep -vE '^\s*(#|$)' "$REPO/archivos.txt")
    echo "   Instalados/actualizados: $nuevos · ya iguales: $iguales · respaldados antes de sobrescribir: $respaldados"
    [ "$respaldados" -gt 0 ] && echo "   Respaldo en: $RESPALDO"
    hacer mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
else
    aviso "   Archivos omitidos."
fi
echo

# ---------- 3) Tema SDDM ----------
if [ "$SDDM" = si ]; then
    azul "3) Pantalla de inicio de sesión (SDDM, tema sddm-astronaut con mis cambios)"
    T=/usr/share/sddm/themes/sddm-astronaut-theme
    BASE="$(cat "$REPO/sddm/sddm-astronaut-theme.commit")"
    PARCHE="$REPO/sddm/sddm-astronaut-theme.patch"
    if confirmar "   ¿Instalar el tema (necesita sudo)?"; then
        if [ ! -d "$T" ]; then
            hacer sudo git clone https://github.com/keyitdev/sddm-astronaut-theme.git "$T"
            hacer sudo git -C "$T" checkout -q "$BASE"
        fi
        # Del usuario: wallpaper.sh y matugen escriben ahí el fondo y los colores sin sudo
        hacer sudo chown -R "$USER:" "$T"
        if [ "$SIMULAR" = si ]; then
            echo "   [simular] git -C $T apply $PARCHE"
        elif git -C "$T" apply --check "$PARCHE" 2>/dev/null; then
            git -C "$T" apply "$PARCHE" && echo "   Parche aplicado."
        elif git -C "$T" apply --reverse --check "$PARCHE" 2>/dev/null; then
            echo "   El parche ya estaba aplicado."
        else
            aviso "   El parche no encaja con tu copia del tema (¿versión distinta de ${BASE:0:7}?). Revisa $PARCHE a mano."
        fi
        # Tema anterior (opcional, no activo)
        hacer sudo mkdir -p /usr/share/sddm/themes/niri-matugen
        hacer sudo cp "$REPO"/sddm/niri-matugen/* /usr/share/sddm/themes/niri-matugen/
        hacer sudo chown -R "$USER:" /usr/share/sddm/themes/niri-matugen
        # Elegir el tema (respaldo del archivo anterior si existe y es distinto)
        C=/etc/sddm.conf.d/theme.conf
        if [ -f "$C" ] && ! cmp -s "$C" "$REPO/sddm/sddm.conf.d/theme.conf"; then
            hacer mkdir -p "$RESPALDO/etc-sddm.conf.d"
            hacer cp "$C" "$RESPALDO/etc-sddm.conf.d/theme.conf"
        fi
        hacer sudo install -Dm644 "$REPO/sddm/sddm.conf.d/theme.conf" "$C"
    else
        aviso "   SDDM omitido."
    fi
else
    azul "3) SDDM: omitido (--sin-sddm)"
fi
echo

# ---------- 4) Qué falta ----------
azul "4) Últimos pasos (hazlos tú)"
cat <<EOF
   • Servicios (si aún no están activos):
       sudo systemctl enable --now NetworkManager bluetooth power-profiles-daemon
       sudo systemctl enable sddm        # solo si no usas otro gestor de inicio de sesión
   • Copia algunas imágenes o vídeos a ~/Pictures/wallpapers/
   • Cierra sesión, elige "niri" en SDDM y entra.
   • Abre la galería con Super+Shift+W y elige un fondo: matugen pintará todo con sus colores.
EOF
[ "$SIMULAR" = si ] && aviso "Fin de la simulación: no se cambió nada."
exit 0
