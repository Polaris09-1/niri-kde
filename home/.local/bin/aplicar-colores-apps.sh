#!/usr/bin/env bash
# Aplica los colores de matugen a las apps GTK y Qt/KDE (2026-11-01).
# Lo llama wallpaper.sh justo después de matugen. También se puede correr a mano.
# Lee el modo (dark/light) de ~/.local/share/color-schemes/Matugen.colors (línea "# modo=...").
set -u

ESQUEMA="$HOME/.local/share/color-schemes/Matugen.colors"
KDEGLOBALS="$HOME/.config/kdeglobals"
LOG="${XDG_RUNTIME_DIR:-/tmp}/aplicar-colores-apps.log"
exec >>"$LOG" 2>&1
echo "== $(date '+%F %T')"

modo=$(sed -n 's/^# modo=\(dark\|light\)$/\1/p' "$ESQUEMA" 2>/dev/null | head -1)
[ -n "$modo" ] || modo=dark

if [ "$modo" = light ]; then
    tema_gtk=adw-gtk3; preferencia=prefer-light; iconos=Papirus-Light
else
    tema_gtk=adw-gtk3-dark; preferencia=prefer-dark; iconos=Papirus-Dark
fi

# 1) GTK: tema, claro/oscuro (lo leen también libadwaita y Firefox) e iconos.
#    Cambiar el tema y volverlo a poner obliga a las apps GTK3 abiertas a releer gtk.css.
gs=org.gnome.desktop.interface
gsettings set $gs color-scheme "$preferencia"
gsettings set $gs icon-theme "$iconos"
if [ "$(gsettings get $gs gtk-theme)" = "'$tema_gtk'" ]; then
    gsettings set $gs gtk-theme Adwaita
    sleep 0.2
fi
gsettings set $gs gtk-theme "$tema_gtk"

# 2) Qt (qt5ct / qt6ct): iconos según el modo. Los colores ya los escribió matugen.
for conf in "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"; do
    [ -f "$conf" ] && sed -i "s/^icon_theme=.*/icon_theme=$iconos/" "$conf"
done

# 3) KDE (Dolphin, Discover, Filelight): copia los grupos de colores a kdeglobals
#    sin tocar los demás ajustes que esas apps guardan ahí.
if [ -f "$ESQUEMA" ]; then
    python3 -I - "$ESQUEMA" "$KDEGLOBALS" "$iconos" <<'PY'
import configparser, os, sys
esquema, destino, iconos = sys.argv[1:4]
def leer(ruta):
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",))
    cp.optionxform = str
    if os.path.exists(ruta):
        cp.read(ruta, encoding="utf-8")
    return cp
src, dst = leer(esquema), leer(destino)
for sec in list(dst.sections()):
    if sec.startswith("Colors:") or sec in ("ColorEffects:Disabled", "ColorEffects:Inactive", "WM"):
        dst.remove_section(sec)
for sec in src.sections():
    if not dst.has_section(sec):
        dst.add_section(sec)
    for k, v in src.items(sec):
        dst.set(sec, k, v)
# Sin esto, KDE Frameworks 6 aplica su BreezeLight interno fuera de Plasma.
if not dst.has_section("UiSettings"):
    dst.add_section("UiSettings")
dst.set("UiSettings", "ColorScheme", "Matugen")
if not dst.has_section("Icons"):
    dst.add_section("Icons")
dst.set("Icons", "Theme", iconos)
tmp = destino + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    dst.write(f, space_around_delimiters=False)
os.replace(tmp, destino)
PY
    # Avisa a las apps KDE abiertas para que se repinten (0 = paleta, 4 = iconos).
    dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 || true
    dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged int32:0 || true
fi
echo "modo=$modo tema=$tema_gtk iconos=$iconos"
