#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

# ── Todas las preguntas PRIMERO, sin ejecutar nada todavía ───────────────────
echo -e "\n=== Instalador macOS Ventura XFCE ==="
if [ -t 0 ]; then
    read -p "¿Qué modo quieres? (light/dark): " MODO </dev/tty
fi
MODO="${MODO:-dark}"
MODO=$(echo "$MODO" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

if [ -t 0 ]; then
    echo ""
    read -p "¿Optimizar servicios del sistema (desactivar ModemManager, CUPS, etc.)? [S/n]: " resp_opt </dev/tty
fi
OPTIMIZAR="${resp_opt:-s}"
OPTIMIZAR=$(echo "$OPTIMIZAR" | tr '[:upper:]' '[:lower:]')

if [ -t 0 ]; then
    echo ""
    read -p "¿Instalar regla visudo para no teclear la contraseña de sudo durante el proceso? [S/n]: " resp_visudo </dev/tty
fi
VISUDO="${resp_visudo:-s}"
VISUDO=$(echo "$VISUDO" | tr '[:upper:]' '[:lower:]')

if [ -t 0 ]; then
    echo ""
    read -p "¿Corregir permisos recursivos en carpetas de usuario (Escritorio, Descargas, Documentos, etc.)? [S/n]: " resp_perm </dev/tty
else
    resp_perm="s"
fi
resp_perm="${resp_perm:-s}"
resp_perm=$(echo "$resp_perm" | tr '[:upper:]' '[:lower:]')

# ── Contraseña sudo SIEMPRE AL FINAL de todas las preguntas ─────────────────
info "Se pedirá la contraseña una sola vez para todo el proceso"
if [ -t 0 ]; then
    sudo -v
else
    askpass=$(mktemp)
    cat > "$askpass" << 'ASKEOL'
#!/bin/bash
zenity --password --title="Contraseña sudo" 2>/dev/null
ASKEOL
    chmod +x "$askpass"
    SUDO_ASKPASS="$askpass" sudo -A true 2>/dev/null || true
    rm -f "$askpass"
fi
if sudo -n true 2>/dev/null; then
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    PID_SUDO=$!
    trap 'kill $PID_SUDO 2>/dev/null || true' EXIT
fi

# Regla visudo: que el instalador y las herramientas GUI (p. ej. gestores de
# paquetes) puedan usar sudo sin teclear la contraseña a cada rato. La regla se
# valida con visudo -cf ANTES de instalarla en /etc/sudoers.d/ y el temporal se
# limpia pase lo que pase; si no hay sudo disponible se omite sin romper nada.
if [ "$VISUDO" = "s" ]; then
    if sudo -n true 2>/dev/null; then
        visudo_usuario=$(echo "$USER" | tr -cd 'A-Za-z0-9_-')
        if [ -n "$visudo_usuario" ]; then
            visudo_tmp=$(mktemp)
            echo "$visudo_usuario ALL=(ALL:ALL) NOPASSWD: ALL" > "$visudo_tmp"
            if sudo -n visudo -cf "$visudo_tmp" 2>/dev/null && \
               sudo -n install -m 0440 -o root -g root "$visudo_tmp" "/etc/sudoers.d/$visudo_usuario"; then
                info "Regla visudo instalada para $visudo_usuario (sudo sin contraseña)"
            else
                warn "No se instaló la regla visudo: no pasó la validación (visudo -cf)"
            fi
            rm -f "$visudo_tmp"
        fi
    fi
fi

if [ "$OPTIMIZAR" = "s" ]; then
    bash "$DIR/optimizar.sh" systemd
fi

step "1/9 Limpiando sesión XFCE y archivos previos"
pkill -9 xfce4-panel 2>/dev/null || true
pkill -9 xfconfd      2>/dev/null || true
pkill -9 plank        2>/dev/null || true
sleep 3

rm -rf ~/.config/xfce4
rm -rf ~/.config/xfce4-dict
rm -rf ~/.cache/xfce4
rm -rf ~/.cache/sessions
rm -rf ~/.icons/WhiteSur* ~/.icons/custom

# Fix: corregir permisos (la pregunta ya se hizo al inicio)
    if [ "$resp_perm" = "s" ]; then
        bash "$DIR/aplicaciones.sh" "$MODO" fix_permisos_usuario
    else
        info "Permisos omitidos por usuario"
    fi
rm -rf ~/.themes/WhiteSur*

# ── Forzar CSD global para que Nautilus tenga estilo macOS ──
export GTK_CSD=1
for rc in ~/.profile ~/.xprofile ~/.bashrc; do
    grep -q 'GTK_CSD=1' "$rc" 2>/dev/null || echo 'export GTK_CSD=1' >> "$rc"
done
mkdir -p ~/.config/environment.d
grep -q 'GTK_CSD=1' ~/.config/environment.d/csd.conf 2>/dev/null || \
    echo 'GTK_CSD=1' >> ~/.config/environment.d/csd.conf

bash "$DIR/aplicaciones.sh" "$MODO" appmenu

bash "$DIR/tema.sh" "$MODO" dependencias

bash "$DIR/tema.sh" "$MODO" instalar

step "Clonando repositorio ventura-xfce"
verificar_clon "ventura-xfce" "https://github.com/ibm-7094a/ventura-xfce"
info "Repositorio clonado"

bash "$DIR/aplicaciones.sh" "$MODO" ulauncher

bash "$DIR/nautilus.sh" "$MODO" configurar

bash "$DIR/nautilus.sh" "$MODO" ocultar

bash "$DIR/nautilus.sh" "$MODO" extension

# Files (Nautilus) con ventana translúcida
bash "$DIR/nautilus.sh" "$MODO" transparencia


bash "$DIR/tema.sh" "$MODO" gtk-repo

bash "$DIR/tema.sh" "$MODO" iconos

bash "$DIR/tema.sh" "$MODO" fuentes

bash "$DIR/panel.sh" "$MODO" configurar

bash "$DIR/panel.sh" "$MODO" plank

# Fix: forzar launcher 'settings' a xfce4-settings-manager (ya se hace en panel_plank)

bash "$DIR/tema.sh" "$MODO" aplicar

bash "$DIR/tema.sh" "$MODO" xfwm

# Sin fundido/animaciones en los menús (clic derecho)
bash "$DIR/tema.sh" "$MODO" animaciones

# Forzar botones macOS en xfwm4 por si no se aplicó
xfconf-query -c xfwm4 -p /general/button_layout -s "CMH|" 2>/dev/null || true
xfconf-query -c xfwm4 -p /general/title_alignment -s "center" 2>/dev/null || true

bash "$DIR/terminal.sh" "$MODO" konsole

bash "$DIR/terminal.sh" "$MODO" default

bash "$DIR/terminal.sh" "$MODO" zsh

bash "$DIR/aplicaciones.sh" "$MODO" autostart

# Wallpaper (antes estaba en lightdm.sh, que ya no existe)
descargar_fondo || true
aplicar_fondo_escritorio || true

bash "$DIR/panel.sh" "$MODO" reiniciar

# Forzar decoraciones CSD macOS ANTES de relanzar Nautilus
export GTK_CSD=1
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
if command -v dconf &>/dev/null; then
    dconf write /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'" 2>/dev/null || true
fi

bash "$DIR/final.sh" "$MODO" recargar

bash "$DIR/nautilus.sh" "$MODO" relanzar

# Asegurar que ningún separador del panel se expanda
source "$DIR/comun.sh"
source "$DIR/panel.sh"
_panel_expand_false "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
_panel_last_separator_no_expand "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

# ── Optimización de arranque ──
bash "$DIR/optimizar.sh" all

# Fix navegador: reajustar ventanas Chromium con geometría corrupta
# (pantalla completa sin maximizar tras los reinicios de panel/xfconfd)
reparar_ventanas_navegador

bash "$DIR/final.sh" "$MODO" resumen
