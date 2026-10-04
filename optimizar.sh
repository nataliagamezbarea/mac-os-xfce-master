#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"
source "$DIR/picom.sh"

# Redefinir funciones con output simple (sin colores ni unicode)
step() { echo "==> $1"; }
info() { echo "  + $1"; }
warn() { echo "  - $1"; }
error() { echo "  !! $1"; }

# ── Seguridad de arranque ──────────────────────────────────────────────
# Un kernel que se instala a medias (típico: un módulo DKMS que no compila,
# p.ej. virtualbox-dkms contra un kernel más nuevo) deja una entrada de GRUB
# apuntando a un kernel SIN initrd. Al encender, el kernel arranca y muere con
# "VFS: unable to mount root fs" / "Kernel panic - not syncing". Y si además el
# menú está oculto (GRUB_TIMEOUT=0 + hidden) no hay forma de elegir otro kernel.
#
# Estas funciones comprueban que el equipo SIEMPRE queda arrancable y nunca
# borran el kernel que está en uso.

verificar_arranque_seguro() {
    local cfg="/boot/grub/grub.cfg"
    local rotos malos v good

    # grub.cfg es root-only (600): hace falta sudo para leerlo
    [ -r "$cfg" ] || sudo test -r "$cfg" || return 0

    # 1) dpkg no puede tener paquetes a medias (iU/iF/iH/iG/rU/re)
    rotos=$(dpkg -l 2>/dev/null | awk '$1 ~ /^(iU|iF|iH|iG|rU|re)$/ {print $2}')
    if [ -n "$rotos" ]; then
        error "Hay paquetes a medio instalar: $(echo $rotos | tr '\n' ' ')"
        error "Suelen ser kernels sin initrd = panic en el siguiente arranque."
        error "Arreglalo con:  sudo dpkg --configure -a"
        return 1
    fi

    # 2) Cada kernel del menú de GRUB necesita su initrd, y ambos en disco
    [ -f "$cfg" ] || return 0
    malos=0
    good=0
    for v in $(sudo grep -oE "/boot/vmlinuz-[^[:space:]]+" "$cfg" 2>/dev/null |
               sed 's|/boot/vmlinuz-||' | sort -u); do
        if [ ! -f "/boot/vmlinuz-$v" ]; then
            warn "GRUB referencia un kernel inexistente: vmlinuz-$v"
            malos=1
        fi
        if ! sudo grep -q "/boot/initrd.img-$v" "$cfg" 2>/dev/null; then
            error "La entrada de GRUB de $v no tiene initrd  ->  PANIC al arrancar"
            malos=1
        elif [ ! -f "/boot/initrd.img-$v" ]; then
            error "initrd.img-$v no existe en disco  ->  PANIC al arrancar"
            malos=1
        else
            good=1
        fi
    done

    if [ "$good" = 0 ]; then
        error "No queda ningún kernel arrancable. NO reinicies."
        return 1
    fi
    [ "$malos" = 1 ] && return 1
    return 0
}

# Arranque sin letra: el menú de GRUB no se ve nunca (hidden + 0s), para no
# romper el aspecto de arranque. Es lo que quiere el usuario.
#
# AVISO: con TIMEOUT=0 no hay ninguna ventana para abrir el menú a mano. Si una
# actualización deja un kernel roto, no se puede elegir otro sin LIVE USB.
# Por eso verificar_arranque_seguro() es obligatoria: avisa ANTES de que
# llegue a pasar.
asegurar_menu_grub() {
    local grub="/etc/default/grub"
    local timeout_actual
    timeout_actual=$(grep "^GRUB_TIMEOUT=" "$grub" 2>/dev/null | head -1 | cut -d= -f2)
    local estilo_actual
    estilo_actual=$(grep "^GRUB_TIMEOUT_STYLE=" "$grub" 2>/dev/null | head -1 | cut -d= -f2)

    if [ "$timeout_actual" != "0" ] || [ "$estilo_actual" != "hidden" ]; then
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub"
        sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$grub"
        sudo update-grub &>/dev/null || true
        info "GRUB: arranque sin menú (0s)"
    fi
}

# Marca el kernel en uso como "manual" para que ningún apt/autoremove lo borre.
proteger_kernel_activo() {
    local kmod
    kmod=$(uname -r)
    sudo apt-mark manual "linux-image-$kmod" "linux-modules-$kmod" \
        "linux-modules-extra-$kmod" "linux-headers-$kmod" &>/dev/null || true
}

optimizar_systemd() {
    step "Optimizando servicios del sistema"

    local sugerencias=(
        "ModemManager.service:Modulem 4G/5G (si no usas datos moviles)"
        "cups.service:Impresion (si no tienes impresora)"
        "avahi-daemon.service:Avahi (descubrimiento mDNS/Zeroconf)"
        "cups-browsed.service:Deteccion automatica de impresoras"
    )

    for sugerencia in "${sugerencias[@]}"; do
        local unidad="${sugerencia%%:*}"
        local desc="${sugerencia#*:}"

        if systemctl is-enabled "$unidad" &>/dev/null 2>&1; then
            sudo systemctl disable "$unidad" 2>/dev/null || true
            sudo systemctl stop "$unidad" 2>/dev/null || true
            info "$unidad desactivado"
        fi
    done
}

optimizar_autostart() {
    step "Optimizando autostart (menos espera al iniciar sesion)"

    local AUTOSTART="$HOME/.config/autostart"

    # ── Plank: máxima prioridad ──
    # Con X-XFCE-Autostart-Phase=Initialization arranca en la fase más temprana
    # del login (antes que el resto), por lo que los demás no le retrasan. Si aún
    # quedara una entrada antigua "plank.desktop", se limpia para no duplicarlo.
    local plank_auto="$AUTOSTART/00-plank.desktop"
    if [ ! -f "$plank_auto" ] && [ -f "$AUTOSTART/plank.desktop" ]; then
        mv -f "$AUTOSTART/plank.desktop" "$plank_auto" 2>/dev/null || true
    fi
    if [ -f "$plank_auto" ]; then
        grep -q '^X-XFCE-Autostart-Phase=Initialization$' "$plank_auto" || \
            echo "X-XFCE-Autostart-Phase=Initialization" >> "$plank_auto"
        sed -i 's/sleep [0-9]*/sleep 1/' "$plank_auto"
        # XFCE no expande "$HOME" ni "/home/USER/" en la línea Exec=.
        # Forzamos la ruta absoluta por si la entrada vieja traía "$HOME" literal
        # (causa habitual de que Plank no arranque al encender el PC).
        sed -i "s|\$HOME/|$HOME/|g; s|/home/USER/|$HOME/|g" "$plank_auto"
        info "plank: fase Initialization (primero) + arranque sin retraso"
    fi

    if [ -f "$AUTOSTART/ulauncher.desktop" ]; then
        sed -i 's/sleep [0-9]*/sleep 2/' "$AUTOSTART/ulauncher.desktop"
        info "ulauncher: sleep 2s"
    fi

    # Limpiar restos de versiones antiguas: este autostart relanzaba un segundo
    # xfdesktop en cada login y hacía "colapsar" el fondo/al escritorio al reiniciar.
    if [ -f "$AUTOSTART/xfdesktop-restart.desktop" ]; then
        warn "Eliminando xfdesktop-restart.desktop (causaba colapso del fondo)"
        rm -f "$AUTOSTART/xfdesktop-restart.desktop"
    fi

    # ── Miniaplicación de red (nm-applet): asegurar que arranca sola ──
    if [ -f "$AUTOSTART/nm-applet.desktop" ]; then
        sed -i 's/^Hidden=true/Hidden=false/; s/^X-GNOME-Autostart-enabled=false/X-GNOME-Autostart-enabled=true/' \
            "$AUTOSTART/nm-applet.desktop" 2>/dev/null || true
        info "nm-applet: autostart activado"
    fi
}

optimizar_kernel() {
    step "Ajustes de rendimiento del kernel"

    local sysctl_file="/etc/sysctl.d/90-desktop-performance.conf"
    local temp=$(mktemp)

    cat > "$temp" << 'SYSCTLEOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.numa_balancing=0
SYSCTLEOF

    if [ -f "$sysctl_file" ]; then
        if ! cmp -s "$temp" "$sysctl_file" 2>/dev/null; then
            sudo cp "$temp" "$sysctl_file"
            sudo sysctl --system &>/dev/null || true
            info "sysctl: swappiness=10, cache pressure=50"
        else
            info "sysctl ya optimizado"
        fi
    else
        sudo cp "$temp" "$sysctl_file"
        sudo sysctl --system &>/dev/null || true
        info "sysctl: swappiness=10, cache pressure=50"
    fi
    rm -f "$temp"
}

optimizar_preload() {
    step "Instalando preload (acelera apertura de apps)"

    if ! dpkg -l preload &>/dev/null 2>&1; then
        apt_silencioso install preload 2>/dev/null || true
        if dpkg -l preload &>/dev/null 2>&1; then
            sudo systemctl enable preload 2>/dev/null || true
            sudo systemctl start preload 2>/dev/null || true
            info "preload instalado"
        else
            warn "preload no disponible"
        fi
    else
        info "preload ya instalado"
    fi
}

optimizar_boot() {
    step "Acelerando arranque (GRUB + GPU manager)"

    if systemctl is-enabled gpu-manager &>/dev/null 2>&1; then
        sudo systemctl disable gpu-manager.service 2>/dev/null || true
        sudo systemctl mask gpu-manager.service 2>/dev/null || true
        info "gpu-manager desactivado"
    else
        info "gpu-manager ya desactivado"
    fi

    if grep -q "splash" /etc/default/grub 2>/dev/null; then
        sudo sed -i 's/quiet splash/quiet/g' /etc/default/grub
        sudo update-grub &>/dev/null || true
        info "Plymouth (splash) desactivado"
    else
        info "GRUB ya sin splash"
    fi

    # Antes de tocar nada del arranque: comprobar que el equipo sigue siendo
    # arrancable. Con el menú oculto no hay segunda oportunidad sin LIVE USB.
    if ! verificar_arranque_seguro; then
        error "Arranque inseguro. Se omite tocar GRUB para no empeorarlo."
        return 1
    fi
    proteger_kernel_activo

    # Menú de GRUB sin letras y sin espera: hidden + 0s.
    asegurar_menu_grub
    local _t
    _t=$(grep "^GRUB_TIMEOUT=" /etc/default/grub 2>/dev/null | head -1 | cut -d= -f2)
    info "GRUB_TIMEOUT en $_t"
}

optimizar_profundidad() {
    step "Optimizacion profunda: servicios + CPU + kernel"

    FWUPD=0; APT=0; E2SCRUB=0; ACCOUNTS=0; NMWAIT=0; KERNELOOPS=0; APPORT=0
    GOV=0; ZRAM=0; WATCHDOG=0

    if systemctl is-enabled fwupd-refresh &>/dev/null 2>&1; then
        sudo systemctl mask fwupd-refresh.service 2>/dev/null || true
        FWUPD=1
    fi
    if systemctl is-enabled fwupd &>/dev/null 2>&1; then
        sudo systemctl mask fwupd.service 2>/dev/null || true
    fi

    for svc in apt-daily.service apt-daily-upgrade.service; do
        if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
            sudo systemctl mask "$svc" 2>/dev/null || true
            APT=1
        fi
    done

    if systemctl is-enabled e2scrub_reap &>/dev/null 2>&1; then
        sudo systemctl mask e2scrub_reap.service 2>/dev/null || true
        E2SCRUB=1
    fi

    if systemctl is-enabled accounts-daemon &>/dev/null 2>&1; then
        sudo systemctl mask accounts-daemon.service 2>/dev/null || true
        ACCOUNTS=1
    fi

    if systemctl is-enabled NetworkManager-wait-online &>/dev/null 2>&1; then
        sudo systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
        NMWAIT=1
    fi

    # También desactivar systemd-networkd-wait-online por si usa networkd
    if systemctl is-enabled systemd-networkd-wait-online &>/dev/null 2>&1; then
        sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
        NMWAIT=1
    fi

    # Evitar que unidades del usuario esperen red: quitar After=network-online.target de servicios gráficos
    for svc in lightdm.service display-manager.service; do
        if systemctl cat "$svc" 2>/dev/null | grep -q 'After=.*network-online.target'; then
            sudo mkdir -p "/etc/systemd/system/$svc.d"
            printf '[Unit]\nAfter=\nWants=\n' | sudo tee "/etc/systemd/system/$svc.d/no-wait-network.conf" &>/dev/null
            sudo systemctl daemon-reload
            info "$svc: quitado After=network-online.target"
        fi
    done

    if systemctl is-enabled kerneloops &>/dev/null 2>&1; then
        sudo systemctl mask kerneloops.service 2>/dev/null || true
        KERNELOOPS=1
    fi

    if systemctl is-enabled apport &>/dev/null 2>&1; then
        sudo systemctl mask apport.service 2>/dev/null || true
        APPORT=1
    fi

    if command -v cpupower &>/dev/null; then
        sudo cpupower frequency-set -g performance &>/dev/null || true
        GOV=1
    elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null || true
        GOV=1
    fi

    local gov_rule="/etc/udev/rules.d/99-cpu-governor.rules"
    if [ ! -f "$gov_rule" ]; then
        echo 'ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="performance"' | \
            sudo tee "$gov_rule" &>/dev/null || true
    fi

    local grub="/etc/default/grub"
    if ! grep -q "nowatchdog" "$grub" 2>/dev/null; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog /' "$grub"
        sudo update-grub &>/dev/null || true
        WATCHDOG=1
    fi

    if ! systemctl is-enabled zram-setup &>/dev/null 2>&1; then
        sudo tee /etc/systemd/system/zram-setup.service << 'SERVICEEOF' &>/dev/null
[Unit]
Description=Swap comprimido zram
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "modprobe zram && zramctl -f --size 8G --algorithm zstd && mkswap /dev/zram0 && swapon -p 100 /dev/zram0"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF
        sudo systemctl enable zram-setup.service &>/dev/null || true
        sudo systemctl start zram-setup.service &>/dev/null || true
        ZRAM=1
    else
        ZRAM_ALREADY=1
    fi

    echo ""
    [ "$FWUPD" = 1 ]     && info "fwupd-refresh desactivado"      || info "fwupd-refresh ya desactivado"
    [ "$APT" = 1 ]       && info "apt-daily desactivado"           || info "apt-daily ya desactivado"
    [ "$E2SCRUB" = 1 ]   && info "e2scrub_reap desactivado"       || info "e2scrub_reap ya desactivado"
    [ "$ACCOUNTS" = 1 ]  && info "accounts-daemon desactivado"    || info "accounts-daemon ya desactivado"
    [ "$NMWAIT" = 1 ]    && info "NM-wait-online desactivado"     || info "NM-wait-online ya desactivado"
    [ "$KERNELOOPS" = 1 ]&& info "kerneloops desactivado"         || info "kerneloops ya desactivado"
    [ "$APPORT" = 1 ]    && info "apport desactivado"             || info "apport ya desactivado"
    [ "$GOV" = 1 ]       && info "CPU governor = performance"     || info "CPU governor ya en performance"
    [ "$WATCHDOG" = 1 ]  && info "nowatchdog anadido a kernel"    || info "nowatchdog ya presente"
    [ "$ZRAM" = 1 ]      && info "zram activado (8G zstd)"
    [ "$ZRAM_ALREADY" = 1 ] && info "zram ya activado"
}

optimizar_energia() {
    step "Configurando gestor de energía (tapa → lock, sin pantalla negra)"

    # 1. systemd-logind: cerrar tapa = bloquear (no suspender/hibernar)
    local logind_conf="/etc/systemd/logind.conf"
    local logind_tmp=$(mktemp)
    sudo cp "$logind_conf" "$logind_tmp" 2>/dev/null || true

    # Asegurar claves necesarias
    grep -q '^HandleLidSwitch=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitch=lock' >> "$logind_tmp"
    grep -q '^HandleLidSwitchExternalPower=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitchExternalPower=lock' >> "$logind_tmp"
    grep -q '^HandleLidSwitchDocked=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitchDocked=ignore' >> "$logind_tmp"
    grep -q '^LidSwitchIgnoreInhibited=' "$logind_tmp" 2>/dev/null || echo 'LidSwitchIgnoreInhibited=no' >> "$logind_tmp"

    # Reemplazar valores si ya existen
    sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=lock/' "$logind_tmp"
    sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' "$logind_tmp"
    sed -i 's/^#*HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$logind_tmp"
    sed -i 's/^#*LidSwitchIgnoreInhibited=.*/LidSwitchIgnoreInhibited=no/' "$logind_tmp"

    if ! cmp -s "$logind_tmp" "$logind_conf" 2>/dev/null; then
        sudo cp "$logind_tmp" "$logind_conf"
        sudo systemctl restart systemd-logind 2>/dev/null || true
        info "systemd-logind: tapa → lock (externo/dock ignorado)"
    else
        info "systemd-logind ya configurado"
    fi
    rm -f "$logind_tmp"

    # 2. xfce4-power-manager: mismo comportamiento + no apagar pantalla al bloquear
    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-battery -s 1 2>/dev/null || true      # 1 = lock
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-ac -s 1 2>/dev/null || true          # 1 = lock
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s true 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch -s true 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery -s 0 2>/dev/null || true          # no apagar pantalla batería
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac -s 0 2>/dev/null || true              # no apagar pantalla AC
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -s 0 2>/dev/null || true
        info "xfce4-power-manager: tapa → lock, pantalla siempre encendida"
    fi

    # 3. BLOQUEO con xfce4-screensaver (único bloqueador, sin duplicados).
    #    light-locker 1.8.0 deja la pantalla en negro al desbloquear la 2ª
    #    vez tras cerrar la tapa (bug conocido) → se desactiva.
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
        # Fallback: solo systemd-logind para lock
        xfconf-query -c xfce4-session -p /general/LockCommand -s "loginctl lock-session" 2>/dev/null || true
        info "Lock via systemd-logind (xfce4-screensaver no disponible)"
    fi
    # light-locker desactivado (autostart oculto) para no duplicar bloqueos.
    if command -v light-locker &>/dev/null || [ -f /etc/xdg/autostart/light-locker.desktop ]; then
        cat > ~/.config/autostart/light-locker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Light-locker
Exec=light-locker
Hidden=true
EOF
        pkill -x light-locker 2>/dev/null || true
        info "light-locker desactivado (evita doble bloqueo)"
    fi


    # 4. Hook systemd-sleep: al despertar (resume) recomponer sesión → pantalla ON + plank + xfce4-screensaver + red
    local sleep_hook="/lib/systemd/system-sleep/99-mac-os-xfce-resume"
    sudo tee "$sleep_hook" >/dev/null << 'SLEEPEOF'
#!/bin/bash
# Hook resume: recomponer la sesión tras suspend/hibernate (pantalla ON, plank, locker, red)
case "$1/$2" in
    post/suspend|post/hibernate|post/hybrid-sleep)
        # Esperar un poco a que el kernel termine de reanudar dispositivos
        sleep 2
        # Usuario real (no root)
        REAL_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
        [ -z "$REAL_USER" ] && REAL_USER=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)
        [ -z "$REAL_USER" ] && exit 0
        USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
        export DISPLAY=":0"
        export XAUTHORITY="$USER_HOME/.Xauthority"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus"

        # 0. FORZAR PANTALLA ON (DPMS) - crítico para evitar negro
        sudo -u "$REAL_USER" xset dpms force on 2>/dev/null || true
        sudo -u "$REAL_USER" xset s off 2>/dev/null || true
        sudo -u "$REAL_USER" xset -dpms 2>/dev/null || true
        sudo -u "$REAL_USER" xset s noblank 2>/dev/null || true


        # 2. Reiniciar Plank si no está
        if ! sudo -u "$REAL_USER" pgrep -x plank >/dev/null 2>&1; then
            sudo -u "$REAL_USER" plank >/dev/null 2>&1 &
        fi

        # 3. Asegurar xfce4-screensaver vivo (bloqueo actual); si murió,
        #    relanzarlo para que el próximo bloqueo funcione bien.
        if ! sudo -u "$REAL_USER" pgrep -x xfce4-screensaver >/dev/null 2>&1; then
            sudo -u "$REAL_USER" xfce4-screensaver >/dev/null 2>&1 &
        fi

        # 4. Forzar xfwm4 a redibujar (quita artefactos/negro) con compositor explícito
        # Compositor único: picom (xfwm4 con compositor apagado)
        if command -v picom >/dev/null 2>&1; then
            sudo -u "$REAL_USER" pkill -x picom 2>/dev/null || true
            sudo -u "$REAL_USER" setsid picom --config "$USER_HOME/.config/picom/picom.conf" -b >/dev/null 2>&1 &
        else
            sudo -u "$REAL_USER" xfwm4 --replace --compositor=on 2>/dev/null &
        fi

        # 5. Red: reconectar cableado y asegurar nm-applet / blueman-applet
        nmcli device reapply "$(nmcli -t -f DEVICE,TYPE device | grep ':ethernet' | cut -d: -f1 | head -1)" 2>/dev/null || true
        if ! sudo -u "$REAL_USER" pgrep -x nm-applet >/dev/null 2>&1; then
            sudo -u "$REAL_USER" nm-applet 2>/dev/null &
        fi
        if ! sudo -u "$REAL_USER" pgrep -x blueman-applet >/dev/null 2>&1; then
            sudo -u "$REAL_USER" blueman-applet 2>/dev/null &
        fi
        ;;
esac
SLEEPEOF
    sudo chmod +x "$sleep_hook"
    info "Hook resume systemd-sleep creado (pantalla ON + plank + xfce4-screensaver + xfwm4 + red)"

    # 6. NetworkManager: conexión cableada RÁPIDA (no esperar "online", pero sí conectar ya)
    local nm_conf="/etc/NetworkManager/conf.d/99-wired-fast.conf"
    sudo mkdir -p "$(dirname "$nm_conf")"
    sudo tee "$nm_conf" >/dev/null << 'NMEOF'
[main]
# No esperar conectividad completa para considerar "conectado"
connectivity-check-enabled=false

[device]
# No gestionar wait-online para wired
wired.wait-online=false
NMEOF
    sudo systemctl reload NetworkManager 2>/dev/null || true
    info "NetworkManager: wired rápido (sin wait-online)"
}

optimizar_limpiar() {
    step "Limpiando caches y temporales"

    apt_silencioso autoremove 2>/dev/null || true
    apt_silencioso autoclean 2>/dev/null || true
    journalctl --vacuum-time=7d &>/dev/null || true
    rm -rf ~/.cache/thumbnails/* 2>/dev/null || true
    rm -rf ~/.cache/mozilla/firefox/*/cache2/* 2>/dev/null || true
    info "Caches limpiadas"
}

optimizar_resumen() {
    echo ""
    echo "=== Sistema optimizado ==="
    echo "  + Autostart: sleeps reducidos"
    echo "  + Sysctl:    swappiness=10, cache optim."
    echo "  + Servicios: fwupd, apt, e2scrub, ..."
    echo "  + CPU:       governor performance"
    echo "  + Kernel:    nowatchdog"
    echo "  + zram:      swap comprimida en RAM"
    echo "  + GRUB:      sin splash, sin menu, timeout 0s"
    echo "  + Caches:    limpiadas"
    echo ""
    echo "Reinicia para aplicar todos los cambios."
}

if [ "$1" = "systemd" ]; then optimizar_systemd; fi
if [ "$1" = "autostart" ]; then optimizar_autostart; fi
if [ "$1" = "kernel" ]; then optimizar_kernel; fi
if [ "$1" = "preload" ]; then optimizar_preload; fi
if [ "$1" = "boot" ]; then optimizar_boot; fi
if [ "$1" = "profundidad" ]; then optimizar_profundidad; fi
if [ "$1" = "limpiar" ]; then optimizar_limpiar; fi
if [ "$1" = "energia" ]; then optimizar_energia; fi

if [ -z "$1" ] || [ "$1" = "all" ]; then
    optimizar_autostart
    optimizar_kernel
    optimizar_preload
    optimizar_picocompton
    optimizar_boot
    optimizar_profundidad
    optimizar_energia
    optimizar_limpiar
    optimizar_resumen
fi
