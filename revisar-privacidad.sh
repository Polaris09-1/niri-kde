#!/usr/bin/env bash
# revisar-privacidad.sh — busca datos privados en el repositorio ANTES de subirlo.
# Sale con código 1 si encuentra algo que casi seguro es privado; las "palabras a revisar"
# (password, token…) solo se muestran: en el código del escritorio aparecen legítimamente.
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
grave=0

buscar() {   # buscar <descripción> <grep -E patrón> [grave]
    local desc="$1" patron="$2" esGrave="${3:-}"
    local r
    r="$(grep -rnIE --exclude-dir=.git --exclude=revisar-privacidad.sh -e "$patron" . 2>/dev/null | head -20)"
    if [ -n "$r" ]; then
        echo "-- $desc:"
        echo "$r" | sed 's/^/   /'
        [ -n "$esGrave" ] && grave=1
    fi
}
buscarLiteral() {   # buscarLiteral <descripción> <texto> — sin mostrar el texto buscado en pantalla
    local desc="$1" texto="$2"
    [ "${#texto}" -lt 3 ] && return
    local r
    r="$(grep -rnIF --exclude-dir=.git --exclude=revisar-privacidad.sh -e "$texto" . 2>/dev/null | cut -d: -f1,2 | head -10)"
    if [ -n "$r" ]; then
        echo "-- $desc (en estas líneas):"
        echo "$r" | sed 's/^/   /'
        grave=1
    fi
}

echo "== Revisión de privacidad de $REPO"
buscar "Llaves privadas / SSH" 'BEGIN [A-Z ]*PRIVATE KEY|ssh-(rsa|ed25519) AAAA' grave
buscar "Correos electrónicos" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' grave
buscar "Direcciones MAC" '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' grave
buscar "Direcciones IP" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
buscar "Tokens / API keys con valor" '(api[_-]?key|token|secret|bearer)["'"'"' ]*[:=] *["'"'"'][A-Za-z0-9_\-]{12,}' grave
buscarLiteral "Tu ruta personal ($HOME)" "$HOME"
# Nombres de redes Wi-Fi guardadas (se leen de nmcli en el momento; no se escriben en ningún archivo)
if command -v nmcli >/dev/null; then
    while IFS= read -r red; do
        buscarLiteral "Nombre de una red guardada" "$red"
    done < <(nmcli -t -f NAME connection show 2>/dev/null | grep -vE '^(lo|Wired connection [0-9]+)$')
fi
# Ubicación de la luz nocturna (debe quedar en 0,0 en el repo)
buscar "Coordenadas de la luz nocturna" 'property real (lat|lon): -?([1-9][0-9]*\.[0-9]*|0\.[0-9]*[1-9])' grave
# Diseño del escritorio: sin nombres de archivos ni nombre del saludo
disenos="home/.config/quickshell/escritorio/disenos.json"
if [ -f "$disenos" ] && ! jq -e '[.. | objects | select(has("elementos")) | .elementos[] | select(.tipo == "icono" or .tipo == "grupo" or .opciones.nombre != null)] | length == 0' "$disenos" >/dev/null 2>&1; then
    echo "-- $disenos contiene iconos, grupos o el nombre del saludo (o no se puede leer)"
    grave=1
fi
for privado in clima-ciudad.json recordatorios.json; do
    if find . -path ./.git -prune -o -name "$privado" -print | grep -q .; then
        echo "-- $privado está en el repositorio (ciudad o recordatorios personales)"
        grave=1
    fi
done
# fastfetch: sin usuario, equipo, IP ni red en lo que sale en las capturas
for ff in home/.config/fastfetch/config.jsonc home/.config/matugen/templates/fastfetch.jsonc; do
    if [ -f "$ff" ] && grep -nE '"(title|localip|publicip|wifi|users)" *(,|\}|$)|user-name|host-name' "$ff"; then
        echo "-- $ff muestra usuario, equipo, IP o red (líneas de arriba)"
        grave=1
    fi
done
# Nombre del equipo
buscarLiteral "Nombre del equipo" "$(cat /etc/hostname 2>/dev/null)"

echo "-- Palabras a revisar a mano (normalmente es código que PIDE la contraseña, no una contraseña):"
grep -rnIiE --exclude-dir=.git --exclude=revisar-privacidad.sh -e 'password *[:=] *["'"'"'][^"'"'"']+|passwd *=|psk *=' . | head -10 | sed 's/^/   /'

echo
if [ "$grave" -eq 0 ]; then
    echo "OK: no se encontraron datos privados claros. Revisa igualmente la lista de arriba si hay algo."
else
    echo "ATENCIÓN: hay posibles datos privados (arriba). Corrígelos antes de subir."
fi
exit "$grave"
