#!/usr/bin/env bash
# sincronizar.sh — copia la configuración actual de ESTE equipo al repositorio (para subir cambios).
# No toca tu sistema: solo escribe dentro del repositorio.
#
#   ./sincronizar.sh
#
# - Copia lo que lista archivos.txt desde $HOME a home/ del repositorio.
# - Cambia datos personales por marcadores: tu ruta $HOME → @HOME@, el nombre del reloj → @NOMBRE@
#   (install.sh los vuelve a poner con los datos de quien instale).
# - Convierte los enlaces simbólicos absolutos (Colors.qml) en relativos.
# - Guarda tus cambios al tema SDDM astronaut como parche (no el tema entero).
# - Al final ejecuta revisar-privacidad.sh: revisa su salida antes de hacer commit.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$REPO/home"

echo "== Copiando archivos de $HOME a $DEST"
grep -vE '^\s*(#|$)' "$REPO/archivos.txt" | while IFS= read -r ruta; do
    origen="$HOME/$ruta"
    if [ ! -e "$origen" ] && [ ! -L "$origen" ]; then
        echo "   (no existe, se omite) $ruta"
        continue
    fi
    rm -rf "${DEST:?}/$ruta"
    mkdir -p "$(dirname "$DEST/$ruta")"
    cp -a "$origen" "$DEST/$ruta"
    echo "   $ruta"
done

# Exclusiones privadas (opcional): ~/.config/sincronizar-excluir.txt, fuera del repositorio, un texto por línea.
# Se quita de la copia todo archivo o carpeta cuyo nombre lo contenga y todo enlace que apunte a una ruta que lo
# contenga (sin distinguir mayúsculas). revisar-privacidad.sh falla si aun así se cuela en nombres o contenido.
EXCLUIR="$HOME/.config/sincronizar-excluir.txt"
if [ -r "$EXCLUIR" ]; then
    grep -vE '^\s*(#|$)' "$EXCLUIR" | while IFS= read -r texto; do
        find "$DEST" -depth -iname "*$texto*" -exec rm -rf {} + 2>/dev/null || true
        find "$DEST" -type l | while IFS= read -r enlace; do
            if readlink "$enlace" | grep -qiF -- "$texto"; then rm -f "$enlace"; fi
        done
    done
    echo "   (exclusiones privadas aplicadas)"
fi

# Basura que nunca debe ir al repositorio
find "$DEST" \( -name '*.log' -o -name '*.bak' -o -name '*.tmp' -o -name '*~' -o -name '*.bak.*' \) -print -delete

# Enlaces absolutos dentro de $HOME → relativos (p. ej. dock/Colors.qml → ../hola/Colors.qml)
find "$DEST" -type l | while IFS= read -r enlace; do
    destino="$(readlink "$enlace")"
    case "$destino" in
        "$HOME"/*)
            real="$HOME/${enlace#"$DEST"/}"
            relativo="$(realpath -m --relative-to="$(dirname "$real")" "$destino")"
            ln -sfn "$relativo" "$enlace"
            ;;
    esac
done

# Datos personales → marcadores
grep -rlI --null -F "$HOME" "$DEST" | xargs -0 -r sed -i "s#$HOME#@HOME@#g"
reloj="$DEST/.config/quickshell/escritorio/WidgetReloj.qml"
[ -f "$reloj" ] && sed -i -E 's/(property string nombre: )"[^"]*"/\1"@NOMBRE@"/' "$reloj"

# Escritorio: sin los nombres de tus archivos, tus grupos ni el nombre del saludo (al instalar, los iconos van a los
# primeros huecos y el saludo usa el nombre de la cuenta). Si no se puede limpiar, el archivo no se sube.
disenos="$DEST/.config/quickshell/escritorio/disenos.json"
rm -f "$disenos.corrupto"
# La ciudad del clima y los recordatorios son tuyos: nunca suben
rm -f "$DEST/.config/quickshell/escritorio/clima-ciudad.json" "$DEST/.config/quickshell/escritorio/recordatorios.json"
if [ -f "$disenos" ]; then
    if jq '(.. | objects | select(has("elementos")) | .elementos) |= map(select(.tipo != "icono" and .tipo != "grupo") | del(.opciones.nombre))' \
        "$disenos" > "$disenos.limpio"; then
        mv -f "$disenos.limpio" "$disenos"
    else
        rm -f "$disenos" "$disenos.limpio"
    fi
fi

# Luz nocturna: no subir la ubicación (lat/lon). En el repo queda 0,0; quien instale pone la suya
# en LuzNocturna.qml o en hola/luz-nocturna.json (se crea solo al arrancar)
rm -f "$DEST/.config/quickshell/hola/luz-nocturna.json"
luzq="$DEST/.config/quickshell/hola/LuzNocturna.qml"
[ -f "$luzq" ] && sed -i -E 's/(property real (lat|lon): )-?[0-9.]+/\10.0/' "$luzq"

echo "== Tema SDDM"
mkdir -p "$REPO/sddm"
T=/usr/share/sddm/themes/sddm-astronaut-theme
if [ -d "$T/.git" ]; then
    git -C "$T" diff > "$REPO/sddm/sddm-astronaut-theme.patch"
    git -C "$T" rev-parse HEAD > "$REPO/sddm/sddm-astronaut-theme.commit"
    echo "   parche de sddm-astronaut-theme ($(wc -l < "$REPO/sddm/sddm-astronaut-theme.patch") líneas, base $(cut -c1-7 "$REPO/sddm/sddm-astronaut-theme.commit"))"
fi
if [ -d /usr/share/sddm/themes/niri-matugen ]; then
    mkdir -p "$REPO/sddm/niri-matugen"
    cp -a /usr/share/sddm/themes/niri-matugen/{Main.qml,metadata.desktop,theme.conf} "$REPO/sddm/niri-matugen/"
    echo "   niri-matugen (tema anterior, no activo; sin background.jpg: si lo usas, copia ahí una imagen)"
fi
if [ -f /etc/sddm.conf.d/theme.conf ]; then
    mkdir -p "$REPO/sddm/sddm.conf.d"
    cp /etc/sddm.conf.d/theme.conf "$REPO/sddm/sddm.conf.d/theme.conf"
fi

echo
"$REPO/revisar-privacidad.sh"
