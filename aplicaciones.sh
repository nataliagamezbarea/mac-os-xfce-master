#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

aplicaciones_appmenu() {
    step "AppMenu + StatusNotifier"
    if apt-cache show xfce4-appmenu-plugin &>/dev/null; then
        apt_silencioso install xfce4-appmenu-plugin
        info "AppMenu instalado desde apt"
    else
        warn "Descargando AppMenu desde GitHub..."
        local appmenu_deb="/tmp/appmenu_$$.deb"
        curl -L --retry 3 --max-time 60 -o "$appmenu_deb" \
            "https://github.com/lxde/xfce4-appmenu-plugin/releases/download/v0.8.0/xfce4-appmenu-plugin_0.8.0_amd64.deb"
        local tamano
        tamano=$(stat -c%s "$appmenu_deb" 2>/dev/null || echo 0)
        if [ "$tamano" -gt 10240 ]; then
            apt_silencioso install "$appmenu_deb"
            info "AppMenu instalado desde .deb"
        else
            warn "El .deb está corrupto — se omite AppMenu"
        fi
        rm -f "$appmenu_deb"
    fi
    info "AppMenu + StatusNotifier listos"
}

aplicaciones_ulauncher() {
    step "Instalando Ulauncher"
    cd ~
    local ok=false
    if ! command -v ulauncher &>/dev/null; then
        if add-apt-repository -y ppa:agornostal/ulauncher 2>/dev/null; then
            apt_silencioso update
            apt_silencioso install ulauncher && ok=true
            info "Ulauncher instalado desde PPA"
        fi
    fi
    if ! $ok && ! command -v ulauncher &>/dev/null; then
        warn "PPA no disponible — descargando .deb..."
        local version
        version=$(curl -s https://api.github.com/repos/Ulauncher/Ulauncher/releases/latest | grep '"tag_name"' | cut -d\" -f4)
        [ -z "$version" ] && version="5.15.7"
        curl -L --retry 3 --max-time 60 -o /tmp/ulauncher.deb \
            "https://github.com/Ulauncher/Ulauncher/releases/download/${version}/ulauncher_${version}_all.deb"
        local tamano
        tamano=$(stat -c%s /tmp/ulauncher.deb 2>/dev/null || echo 0)
        if [ "$tamano" -gt 10240 ]; then
            apt_silencioso install /tmp/ulauncher.deb && ok=true
            info "Ulauncher ${version} instalado desde .deb"
        else
            warn "No se pudo descargar Ulauncher"
        fi
    fi
    if command -v ulauncher &>/dev/null; then
        local tema_ul="dark"
        [ "$MODO" = "light" ] && tema_ul="light"
        mkdir -p ~/.config/ulauncher
        cat > ~/.config/ulauncher/settings.json << ULJSON
{
    "hotkey-show-app": "<Control>space",
    "grab-mouse-pointer": true,
    "render-on-screen": "mouse-pointer-monitor",
    "show-indicator-icon": false,
    "terminal-command": "",
    "theme-name": "${tema_ul}"
}
ULJSON
        mkdir -p ~/.config/autostart
        cat > ~/.config/autostart/ulauncher.desktop << 'ULEOF'
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 5 && ulauncher --hide-window"
Name=Ulauncher
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=2
ULEOF
        pkill -9 ulauncher 2>/dev/null || true
        sleep 1
        DISPLAY="${DISPLAY:-:0}" ulauncher --hide-window 2>/dev/null &
        info "Ulauncher configurado (Ctrl+Space)"
    else
        warn "Ulauncher no se instaló"
    fi
}



fix_permisos_usuario() {
    step "Corrigiendo permisos de carpetas de usuario"
    local dirs=("$HOME/Escritorio" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Imágenes" "$HOME/Vídeos" "$HOME/Música" "$HOME/.local" "$HOME/.config")
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            sudo chown -R "$USER:$USER" "$d" 2>/dev/null || true
        fi
    done
    info "Permisos de usuario corregidos"
}

aplicaciones_autostart() {
    step "Configurando autostart"
    mkdir -p ~/.config/autostart
    mkdir -p ~/.local/bin

    # ── Instalar blueman (Bluetooth applet) ──
    if ! command -v blueman-applet &>/dev/null; then
        apt_silencioso install blueman 2>/dev/null || true
    fi

    # ── BLOQUEO: xfce4-screensaver (único bloqueador, sin duplicados).
    #    Sustituye a light-locker: light-locker 1.8.0 deja la pantalla en
    #    negro al desbloquear la 2ª vez tras cerrar la tapa (bug conocido). ──
    if command -v xfce4-screensaver &>/dev/null || [ -f /etc/xdg/autostart/xfce4-screensaver.desktop ]; then
        cat > ~/.config/autostart/xfce4-screensaver.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Xfce Screensaver
Comment=Bloqueo de pantalla (unico bloqueador)
Exec=xfce4-screensaver
Hidden=false
EOF
        xfconf-query -c xfce4-session -p /general/LockCommand -s "xfce4-screensaver-command --lock" 2>/dev/null || true
        info "Bloqueo: xfce4-screensaver (lock fiable)"
    else
        xfconf-query -c xfce4-session -p /general/LockCommand -s "loginctl lock-session" 2>/dev/null || true
    fi
    # light-locker desactivado (autostart oculto) para no duplicar bloqueos.
    # Lo anulamos en ~/.config/autostart (user override) con todas las claves
    # necesarias para que ni XFCE ni GNOME lo arranquen.
    if command -v light-locker &>/dev/null || [ -f /etc/xdg/autostart/light-locker.desktop ]; then
        cat > ~/.config/autostart/light-locker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Light-locker
Exec=light-locker
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
        pkill -x light-locker 2>/dev/null || true
        info "light-locker eliminado del inicio de sesión"
    fi

    # ── Plank: MÁXIMA prioridad en el arranque (INMEDIATO, antes de red) ──
    # .desktop con nombre 00- para orden alfabético + Phase=Initialization
    # Exec con RUTA ABSOLUTA (XFCE no expande $HOME en Exec=)
    local PLANK_AUTOSTART="$HOME/.local/bin/plank-autostart.sh"
    cat > "$PLANK_AUTOSTART" << 'PLANKEOF'
#!/bin/bash
# Plank INMEDIATO - sin esperas, sin logs, sin comprobaciones que bloqueen
# Lanza plank YA y sale. Cachés/iconos en background si hace falta.

# Si ya está corriendo, no hacer nada
pgrep -x plank >/dev/null 2>&1 && exit 0

# LANZAR PLANK YA
plank &

# Actualizar cachés de iconos EN BACKGROUND (no bloquea plank)
(
    for t in "$HOME/.local/share/plank/themes/Ventura" "$HOME/.local/share/plank/themes/Transparent"; do
        [ -d "$t" ] && gtk-update-icon-cache -f -t "$t" >/dev/null 2>&1
    done
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$HOME/.icons/custom" >/dev/null 2>&1
) &

PLANKEOF
    chmod +x "$PLANK_AUTOSTART"

    rm -f ~/.config/autostart/plank.desktop
    cat > ~/.config/autostart/00-plank.desktop << EOF
[Desktop Entry]
Type=Application
Exec=$PLANK_AUTOSTART
Name=Plank
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=0
X-XFCE-Autostart-Phase=Initialization
EOF

    # ── Plank AÚN más temprano: ~/.config/xfce4/xinitrc ──
    # startxfce4 ejecuta este archivo ANTES de la cola de autostart del gestor
    # de sesión → el dock aparece al momento. 00-plank.desktop queda de respaldo
    # (pgrep evita duplicados).
    mkdir -p ~/.config/xfce4
    cat > ~/.config/xfce4/xinitrc << 'XINITEOF'
#!/bin/sh
# Arranque temprano de Plank SIN SALTO: espera a que xfwm4 esté listo (máx 10s).
if [ -n "$DISPLAY" ] && command -v plank >/dev/null 2>&1; then
    (
        i=0
        while [ "$i" -lt 20 ]; do
            pgrep -x xfwm4 >/dev/null 2>&1 && break
            sleep 0.5
            i=$((i + 1))
        done
        pgrep -x plank >/dev/null 2>&1 || plank >/dev/null 2>&1 &
    ) &
fi
# Continuar con el inicio estándar de la sesión XFCE
. /etc/xdg/xfce4/xinitrc
XINITEOF
    chmod 644 ~/.config/xfce4/xinitrc

    # NOTA: ya NO se genera xfdesktop-restart.desktop. Ese autostart lanzaba un
    # segundo xfdesktop en cada login (el de la sesión + este), haciendo que el
    # fondo y el escritorio "colapsen" al reiniciar. El tema de iconos lo aplica
    # xfsettingsd solo; no hace falta reiniciar el escritorio.

    # ── Miniaplicación de red (nm-applet): arranque automático ──
    cat > ~/.config/autostart/nm-applet.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Gestor de red
Comment=Miniaplicación de red
Exec=nm-applet
Icon=network-wireless-symbolic
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=1
EOF
    
    # ── Bluetooth (blueman-applet): arranque automático temprano ──
    cat > ~/.config/autostart/blueman-applet.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth
Comment=Gestor de Bluetooth
Exec=blueman-applet
Icon=bluetooth-symbolic
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=2
EOF
    
    info "Autostart configurado (Plank primero, red, Bluetooth)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA ICONOS

    paso="${2:-todo}"
    case "$paso" in
        appmenu)   aplicaciones_appmenu ;;
        ulauncher) aplicaciones_ulauncher ;;
        autostart) aplicaciones_autostart ;;
        fix_permisos_usuario) fix_permisos_usuario ;;
        todo)
            aplicaciones_appmenu
            aplicaciones_ulauncher
            aplicaciones_autostart
            ;;
    esac
fi
