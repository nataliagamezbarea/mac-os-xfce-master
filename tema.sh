#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

tema_instalar_whitesur() {
    local color=$1
    cd ~/WhiteSur-gtk-theme
    sudo ./install.sh -t default -c "$color" -l 2>/dev/null | grep -v "^$" || true
    local origen="/usr/share/themes/WhiteSur-${color}"
    local destino="$HOME/.themes/WhiteSur-${color}"
    if [ -d "$origen" ]; then
        mkdir -p "$destino"
        cp -r "$origen/." "$destino/"
        info "WhiteSur-${color} copiado a ~/.themes"
    else
        warn "WhiteSur-${color} no encontrado en /usr/share/themes"
    fi
    cd ~
}

tema_dependencias() {
    step "Instalando dependencias"
    apt_silencioso update
    apt_silencioso install git meson ninja-build plank konsole sassc \
        libgtk-3-dev libgtk-3-bin libglib2.0-dev libwnck-3-dev xterm \
        libxcb-xinerama0 libxcb-xinerama0-dev curl unzip dconf-cli \
        libev-dev libconfig-dev libpcre2-dev libxext-dev libxdamage-dev \
        libdrm-dev libgl1-mesa-dev libdbus-1-dev libxcb-composite0-dev \
        libxcb-damage0-dev libxcb-glx0-dev libxcb-image0-dev \
        libxcb-present-dev libxcb-randr0-dev libxcb-render-util0-dev \
        libxcb-shape0-dev libxcb-util-dev libxcb-xfixes0-dev libx11-xcb-dev \
        uthash-dev network-manager-gnome xdotool wmctrl x11-utils
    # libgtk-3-bin  -> gtk-update-icon-cache (arregla iconos en blanco de Plank en el primer arranque)
    # xdotool/wmctrl/x11-utils -> necesarios para agrupar ventanas (Brave->Safari, VirtualBox) bajo el mismo icono de Plank
    info "Dependencias instaladas"
}

tema_instalar() {
    step "Instalando tema WhiteSur GTK"
    cd ~
    verificar_clon "WhiteSur-gtk-theme" "https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
    tema_instalar_whitesur "Light"
    tema_instalar_whitesur "Dark"
    info "Temas instalados:"; ls ~/.themes/ | grep WhiteSur
    cd ~
}

tema_gtk_repo() {
    step "Instalando temas GTK desde el repo"
    mkdir -p ~/.themes
    cp ~/ventura-xfce/gtk/gtkthemes/*.tar.xz ~/.themes/ 2>/dev/null || true
    cd ~/.themes
    tar -xf WhiteSur-Light.tar.xz 2>/dev/null || true
    tar -xf WhiteSur-Dark.tar.xz  2>/dev/null || true
    cd ~/ventura-xfce
}

tema_iconos() {
    step "Instalando iconos y cursores"
    mkdir -p ~/.icons
    cp ~/ventura-xfce/gtk/icons/*.tar.xz ~/.icons/ 2>/dev/null || true
    cd ~/.icons
    tar -xf 01-WhiteSur.tar.xz      2>/dev/null || true
    tar -xf custom.tar.xz            2>/dev/null || true
    tar -xf WhiteSur-cursors.tar.xz  2>/dev/null || true
    cd ~/ventura-xfce
    gtk-update-icon-cache -f -t ~/.icons/"$ICONOS" 2>/dev/null || true

    # ── Aplicar cursor a nivel X11 ──────────────────────────────────────────
    # Sin esto el cursor solo cambia en apps GTK pero no en el escritorio/X11.
    # ~/.icons/default/index.theme es el mecanismo estándar que lee el servidor X.
    mkdir -p ~/.icons/default
    printf '[Icon Theme]\nInherits=WhiteSur-cursors\n' > ~/.icons/default/index.theme

    # También vía update-alternatives si está disponible (Debian/Ubuntu)
    if update-alternatives --list x-cursor-theme &>/dev/null 2>&1; then
        local cursor_path=""
        for p in ~/.icons/WhiteSur-cursors /usr/share/icons/WhiteSur-cursors; do
            [ -f "$p/index.theme" ] && cursor_path="$p/index.theme" && break
        done
        if [ -n "$cursor_path" ]; then
            sudo update-alternatives --install /usr/share/icons/default/index.theme \
                x-cursor-theme "$cursor_path" 50 2>/dev/null || true
            sudo update-alternatives --set x-cursor-theme "$cursor_path" 2>/dev/null || true
        fi
    fi

    # XCURSOR_THEME para sesiones X que no leen xfconf
    grep -q 'XCURSOR_THEME' ~/.profile 2>/dev/null || \
        echo 'export XCURSOR_THEME=WhiteSur-cursors' >> ~/.profile
    grep -q 'XCURSOR_THEME' ~/.xprofile 2>/dev/null || \
        echo 'export XCURSOR_THEME=WhiteSur-cursors' >> ~/.xprofile

    info "Iconos y cursor instalados"
}

tema_fuentes() {
    step "Instalando fuentes"
    cd ~
    apt_silencioso install fonts-inter || (
        curl -L -o /tmp/inter.zip "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
        unzip /tmp/inter.zip -d /tmp/inter
        sudo mkdir -p /usr/share/fonts/Inter
        sudo find /tmp/inter -name "*.ttf" -exec cp {} /usr/share/fonts/Inter/ \;
    )
    sudo fc-cache -f -v
    mkdir -p ~/.local/share/fonts/MesloLGS
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Regular.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Bold.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Italic.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Bold_Italic.ttf
    fc-cache -fv
    info "Fuentes instaladas"
}

tema_aplicar() {
    step "Aplicando temas GTK y XFWM"
    asegurar_xfconfd
    sleep 2
    xfconf-query -c xsettings -p /Net/ThemeName       -s "$TEMA"
    xfconf-query -c xsettings -p /Net/IconThemeName   -s "$ICONOS"
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "WhiteSur-cursors"
    xfconf-query -c xsettings -p /Gtk/FontName        -s "Inter 11"
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
        if [ -f "$f" ]; then
            for kv in \
                "gtk-theme-name=$TEMA" \
                "gtk-icon-theme-name=$ICONOS" \
                "gtk-cursor-theme-name=WhiteSur-cursors" \
                "gtk-font-name=Inter 11"; do
                key="${kv%%=*}"
                if grep -q "^${key}=" "$f" 2>/dev/null; then
                    sed -i "s|^${key}=.*|${kv}|" "$f"
                else
                    sed -i "/^\[Settings\]/a ${kv}" "$f"
                fi
            done
        else
            printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-cursor-theme-name=WhiteSur-cursors\ngtk-font-name=Inter 11\n' \
                "$TEMA" "$ICONOS" > "$f"
        fi
    done
    aplicar_iconos_persistente "$ICONOS"
    [ "$MODO" = "dark" ] && aplicar_modo_oscuro

    # Forzar decoration-layout (macOS: botones a la izquierda)
    for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
        if [ -f "$f" ]; then
            if grep -q "^gtk-decoration-layout=" "$f" 2>/dev/null; then
                sed -i 's|^gtk-decoration-layout=.*|gtk-decoration-layout=close,minimize,maximize:|' "$f"
            else
                sed -i "/^\[Settings\]/a gtk-decoration-layout=close,minimize,maximize:" "$f"
            fi
        fi
    done

    info "Tema GTK aplicado: $TEMA / Iconos: $ICONOS"
}

tema_animaciones() {
    # Quita el fundido/animación de los menús (clic derecho en cualquier sitio):
    #   - XFCE: /Net/MenuFadeDelay = 0 ms (xfce4-panel, xfdesktop, popups)
    #   - GTK:  gtk-enable-animations = false (menús, diálogos, microanimaciones)
    step "Desactivando animaciones y fundido de menús"
    asegurar_xfconfd

    xfconf-query -c xsettings -p /Net/MenuFadeDelay -n -t int -s 0 2>/dev/null \
        || xfconf-query -c xsettings -p /Net/MenuFadeDelay -s 0 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/MenuFadeDelay -s 0 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/ToolbarFadeDelay -n -t int -s 0 2>/dev/null \
        || xfconf-query -c xsettings -p /Net/ToolbarFadeDelay -s 0 2>/dev/null || true

    local f
    for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
        mkdir -p "$(dirname "$f")"
        touch "$f"
        if grep -q "^gtk-enable-animations=" "$f" 2>/dev/null; then
            sed -i 's/^gtk-enable-animations=.*/gtk-enable-animations=false/' "$f"
        elif grep -q "^\[Settings\]" "$f" 2>/dev/null; then
            sed -i "/^\[Settings\]/a gtk-enable-animations=false" "$f"
        else
            printf '[Settings]\ngtk-enable-animations=false\n' > "$f"
        fi
    done

    info "Fundido de menús y animaciones GTK desactivados"
}

tema_xfwm() {
    step "Instalando decoraciones XFWM"
    local xfwm_src="$HOME/WhiteSur-gtk-theme"
    mkdir -p "$HOME/.themes/WhiteSur-Light/xfwm4" "$HOME/.themes/WhiteSur-Dark/xfwm4"
    for color in Light Dark; do
        local origen="/usr/share/themes/WhiteSur-${color}/xfwm4"
        local destino="$HOME/.themes/WhiteSur-${color}/xfwm4"
        if [ -d "$origen" ]; then
            mkdir -p "$destino"; cp -r "$origen/." "$destino/"
        elif [ -d "$xfwm_src/src/other/xfwm4/WhiteSur-${color}" ]; then
            mkdir -p "$destino"; cp -r "$xfwm_src/src/other/xfwm4/WhiteSur-${color}/." "$destino/"
        elif [ -d "$xfwm_src/src/other/xfwm4" ]; then
            mkdir -p "$destino"; cp -r "$xfwm_src/src/other/xfwm4/." "$destino/"
        fi
        local origen_completo="/usr/share/themes/WhiteSur-${color}"
        local destino_completo="$HOME/.themes/WhiteSur-${color}"
        if [ -d "$origen_completo" ]; then
            mkdir -p "$destino_completo"
            cp -r "$origen_completo/." "$destino_completo/"
        fi
    done
    info "Decoraciones XFWM copiadas"
    if [ -d "$HOME/ventura-xfce/gtk/xfwm4" ]; then
        for d in "$HOME/ventura-xfce/gtk/xfwm4"/*/; do
            local nombre; nombre=$(basename "$d")
            mkdir -p "$HOME/.themes/$nombre/xfwm4"
            cp -r "$d." "$HOME/.themes/$nombre/xfwm4/"
        done
        info "xfwm4 extra copiado desde ventura-xfce"
    fi
    xfconf-query -c xfwm4 -p /general/theme            -s "$TEMA_XFWM"
    xfconf-query -c xfwm4 -p /general/title_alignment  -s "center"
    xfconf-query -c xfwm4 -p /general/button_layout    -s "CMH|"
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s false

    # Forzar botones macOS en GTK (Nautilus, etc.) - CSD
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
    if command -v dconf &>/dev/null; then
        dconf write /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'" 2>/dev/null || true
    fi

    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    mkdir -p "$(dirname "$xml")"
    cat > "$xml" << XFWMEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${TEMA_XFWM}"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="button_layout" type="string" value="CMH|"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
  </property>
</channel>
XFWMEOF
    info "xfwm4 configurado: $TEMA_XFWM"
    local dir_tema="$HOME/.themes/$TEMA_XFWM/xfwm4"
    if [ ! -d "$dir_tema" ] || [ -z "$(ls -A "$dir_tema" 2>/dev/null)" ]; then
        local dir_sistema="/usr/share/themes/$TEMA_XFWM/xfwm4"
        if [ -d "$dir_sistema" ]; then
            mkdir -p "$dir_tema"; cp -r "$dir_sistema/." "$dir_tema/"
            info "xfwm4 recuperado desde /usr/share/themes"
        else
            warn "No se encontraron decoraciones xfwm4 para $TEMA_XFWM"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Autostart: la misma comprobacion al iniciar sesion.
#
# Se deja un script en ~/.local/bin y una entrada de autostart que lo ejecuta.
# Asi, si xfwm4, picom, plank o el panel mueren (un cierre, un fallo, un
# suspender), al volver a entrar en sesion se levantan solos y no hay que
# acordarse de abrir este .sh a mano.
#
# El script es autonomous (no depende de este repositorio) y encima vuelve a
# poner el tema de xfwm4 que se guardo en su fichero de estado, para que el
# escritorio salga con el tema puesto aunque alguien lo hubiera cambiado.
tema_sesion_autostart() {
    step "Instalando el autostart de comprobacion de sesion"

    local bin="$HOME/.local/bin"
    mkdir -p "$bin" "$HOME/.config/autostart"

    # Estado: el tema que hay que dejar puesto al arrancar.
    cat > "$HOME/.config/mac-os-xfce-sesion.conf" << ESTADEOF
# Generado por tema.sh. Lo lee ~/.local/bin/asegurar-sesion.sh al arrancar.
TEMA_XFWM="$TEMA_XFWM"
ESTADEOF

    # El candado del panel. Es un fichero aparte para que el autostart del login
    # y el watchdog de abajo compartan exactamente el mismo candado: si no, cada
    # uno con el suyo y el duplicado vuelve.
    cat > "$bin/asegurar-panel.sh" << 'PANEOF'
#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# asegurar-panel.sh — arranca xfce4-panel UNA SOLA VEZ, sin esperar.
#
# POR QUE EXISTE
# El panel puede arrancarlo el sistema por dos sitios a la vez:
#   1. ~/.config/autostart/xfce4-panel.desktop  (plan A)
#   2. ~/.local/bin/asegurar-sesion.sh          (plan B, el watchdog)
# Los dos prueban "si no hay panel, lanzo uno". Sin dormir entremedias, los dos
# ven que no hay panel y lanzan uno cada uno: sale el panel DOBLE, con dos
# hileras de ventanas superpuestas.
#
# SOLUCION: no es un sleep, es un candado (flock).
#   - El primero que llega toma el candado, mira, ve que no hay panel, lo lanza
#     y suelte el candado.
#   - El segundo llega, se queda esperando en el candado (no dormido: espera a
#     que el otro suelte), y cuando por fin lo comprueba el panel YA esta vivo,
#     asi que no lanza nada.
# Resultado: sin espera fija, sin duplicados.
# ─────────────────────────────────────────────────────────────────────────────

# Si no hay pantalla (llamado desde una terminal de root), fuera.
[ -n "${DISPLAY:-}" ] || exit 0

# Fichero del candado. En el /run del usuario si se puede; si no, en la cache.
lock_dir="/run/user/$(id -u)"
[ -d "$lock_dir" ] && [ -w "$lock_dir" ] || lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$lock_dir" 2>/dev/null
lock="$lock_dir/mac-os-xfce-panel.lock"

# --- seccion critica: comprobar y lanzar, sin que otro se cuele por medio ---
exec 9>"$lock" || exit 0
flock 9

if pgrep -x xfce4-panel >/dev/null 2>&1; then
    flock -u 9
    exec 9>&-
    exit 0
fi

setsid -f xfce4-panel >/dev/null 2>&1 </dev/null

# Margen para que el proceso aparezca en pgrep antes de soltarle el candado a
# otro. Sin esto, el segundo podria comprobar demasiado pronto y lanzar otro.
sleep 0.5

flock -u 9
exec 9>&-
PANEOF
    chmod +x "$bin/asegurar-panel.sh"

    # El autostart del login llama al script con candado, no a xfce4-panel a pelo.
    cat > "$HOME/.config/autostart/xfce4-panel.desktop" << PANEOF2
[Desktop Entry]
Type=Application
Name=xfce4-panel
Comment=Barra superior del escritorio
Exec=$bin/asegurar-panel.sh
OnlyShowIn=XFCE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-XFCE-Autostart-Phase=Initialization
PANEOF2

    # OJO: delimitador entrecomillado ('ASEGEOF') a proposito. Sin las comillas
    # el shell expande $DISPLAY, $HOME y $tema_xfwm AL GENERAR el script, y el
    # fichero instalado queda con las variables vacias ([ -r "" ], -s "", etc.).
    # Las variables deben resolverse al ejecutarse, no al escribirse.
    cat > "$bin/asegurar-sesion.sh" << 'ASEGEOF'
#!/bin/bash
# Generado por tema.sh (mac-os-xfce).
#
# Se ejecuta al iniciar sesion y comprueba que esten vivos los 4 procesos de los
# que depende el escritorio:
#   xfwm4        gestor de ventanas; sin el NO hay decoraciones (ni boton de
#                cerrar/minimizar/maximizar)
#   picom        compositor; sin el ni el panel, ni el dock, ni las terminales
#                se ven translucidos
#   plank        el dock
#   xfce4-panel  la barra de arriba
#
# Los cuatro arrancan A LA VEZ y SIN ESPERAS: no hay ni un sleep de reloj.
# Antes este script hacia "comprobar -> lanzar -> dormir 3s -> comprobar el
# siguiente" y tardaba mas de 10s en terminar, por eso el escritorio tardaba.
#
# Como no hay esperas, hace falta un candado por componente: si dos caminos
# intentan arrancarlo en el mismo instante, solo uno gana y el otro se espera
# en el candado (esperar en un candado no es dormir: se espera justo lo que
# tarda el otro, y luego lo ve ya vivo). Asi nunca salen dos paneles, ni dos
# docks, ni dos gestores de ventanas.

# Si no hay pantalla (por ejemplo, llamado desde una terminal de root), fuera.
[ -n "${DISPLAY:-}" ] || exit 0

estado="$HOME/.config/mac-os-xfce-sesion.conf"
tema_xfwm=""
[ -r "$estado" ] && . "$estado" 2>/dev/null
# El fichero de estado define TEMA_XFWM en MAYUSCULAS. Antes aqui se leia
# "tema_xfwm" en minusculas: nunca casaba con nada, asi que el tema de xfwm4
# NO se reaplicaba nunca al arrancar (el panel salia sin el tema puesto).
tema_xfwm="${TEMA_XFWM:-$tema_xfwm}"

# ── candado por componente ───────────────────────────────────────────────────
# $1 = nombre del proceso (para el candado y para pgrep)
# $2 = fichero de configuracion (opcional; solo picom lo usa)
asegurar_uno() {
    local proc="$1" conf="${2:-}"
    local lock_dir="/run/user/$(id -u)"
    [ -d "$lock_dir" ] && [ -w "$lock_dir" ] || \
        lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    mkdir -p "$lock_dir" 2>/dev/null

    exec 8>"$lock_dir/mac-os-xfce-$proc.lock" || return 0
    flock 8

    # Ya hay uno vivo: no se toca. "Levanta solo lo que falte".
    if pgrep -x "$proc" >/dev/null 2>&1; then
        flock -u 8; exec 8>&-; return 0
    fi

    if [ -n "$conf" ]; then
        setsid "$proc" --config "$conf" --daemon >/dev/null 2>&1 </dev/null &
    else
        setsid -f "$proc" >/dev/null 2>&1 </dev/null
    fi

    # Margen minimum para que el proceso sea visible en pgrep antes de soltarle
    # el candado a otro. Es lo unico que se espera, y en fracciones de segundo:
    # sin esto, el que viene detras comprobaria "no hay panel" y lanzaria otro.
    sleep 0.3

    flock -u 8
    exec 8>&-
}

# ── preparacion (barata, va antes) ───────────────────────────────────────────
# El compositor de xfwm4 se deja apagado porque el compositor es picom: si los
# dos se activan pelean y las ventanas se ven raras.
xfconf-query -c xfwm4 -p /general/use_compositing -s false >/dev/null 2>&1 || true

# ── los cuatro, A LA VEZ ────────────────────────────────────────────────────
# En segundo plano y con "wait": todos compiten a la vez, cada uno con su
# candado, y aqui solo se sigue cuando los cuatro han terminado.
asegurar_uno xfwm4       &
asegurar_uno picom "$HOME/.config/picom/picom.conf" &
asegurar_uno plank       &
asegurar_uno xfce4-panel &
wait

# El tema vive en xfconf, asi que se reaplica por si alguien lo cambio.
# OJO: no se relanza xfwm4 con --replace. Con ventanas ya abiertas eso les
# descuadra el marco (borde, tamano, esquinas). Solo se arranca si no habia
# ninguno, y de eso ya se encarga el candado de arriba.
[ -n "$tema_xfwm" ] && \
    xfconf-query -c xfwm4 -p /general/theme -s "$tema_xfwm" >/dev/null 2>&1

exit 0
ASEGEOF
    chmod +x "$bin/asegurar-sesion.sh"

    cat > "$HOME/.config/autostart/99-asegurar-sesion.desktop" << AUTOSEOF
[Desktop Entry]
Type=Application
Name=Comprobar sesion (xfwm4, picom, plank, panel)
Comment=Levanta lo que falte para que el escritorio tenga decoraciones y transparencia
Exec=$bin/asegurar-sesion.sh
OnlyShowIn=XFCE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSEOF

    info "autostart instalado: $bin/asegurar-sesion.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; TEMA_XFWM="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; TEMA_XFWM="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA TEMA_XFWM ICONOS

    paso="${2:-todo}"
    case "$paso" in
        dependencias) tema_dependencias ;;
        instalar)     tema_instalar ;;
        gtk-repo)     tema_gtk_repo ;;
        iconos)       tema_iconos ;;
        fuentes)      tema_fuentes ;;
        aplicar)      tema_aplicar ;;
        animaciones)  tema_animaciones ;;
        xfwm)         tema_xfwm ;;
        sesion)       tema_sesion_autostart ;;
        todo)
            tema_dependencias
            tema_instalar
            tema_gtk_repo
            tema_iconos
            tema_fuentes
            tema_aplicar
            tema_animaciones
            tema_xfwm
            tema_sesion_autostart
            ;;
    esac
fi
