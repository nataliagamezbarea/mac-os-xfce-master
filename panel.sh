#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

# Repositorio base del tema macOS Ventura para XFCE.
# Se clona solamente si no existe. Si ya existe un clon válido, se reutiliza.
_panel_asegurar_repositorio() {
    local repo_url="https://github.com/ibm-7094a/ventura-xfce.git"
    local repo_dir="$HOME/ventura-xfce"

    if [ -d "$repo_dir/.git" ]; then
        info "Repositorio ventura-xfce encontrado: $repo_dir"
        return 0
    fi

    if [ -e "$repo_dir" ]; then
        local respaldo="${repo_dir}.backup-$(date +%Y%m%d-%H%M%S)"
        warn "Existe $repo_dir pero no es un repositorio Git"
        warn "Se conservará como $respaldo y se clonará el repositorio oficial"
        if ! mv "$repo_dir" "$respaldo"; then
            warn "No se pudo apartar $repo_dir; no se puede clonar de forma segura"
            return 1
        fi
    fi

    command -v git >/dev/null 2>&1 || {
        warn "Git no está instalado; no se puede clonar ventura-xfce"
        return 1
    }

    step "Clonando repositorio ventura-xfce"
    if git clone "$repo_url" "$repo_dir"; then
        info "Repositorio clonado en $repo_dir"
        return 0
    fi

    warn "No se pudo clonar $repo_url"
    return 1
}


_panel_autostart_wifi() {
    # Configurar el gestor wifi para que se inicie automáticamente
    local wifi_app="nm-applet"
    if command -v "$wifi_app" &>/dev/null; then
        local autostart_dir="$HOME/.config/autostart"
        mkdir -p "$autostart_dir"
        local autostart_file="$autostart_dir/nm-applet.desktop"
        if [ ! -f "$autostart_file" ]; then
            cat > "$autostart_file" << 'WIFIEOF'
[Desktop Entry]
Type=Application
Name=Network Manager Applet
Comment=Network Manager
Exec=nm-applet
Icon=nm-device-wireless
X-GNOME-Autostart-enabled=true
X-MATE-Autostart-enabled=true
Hidden=false
NoDisplay=false
X-Autostart-Priority=1
WIFIEOF
            info "Gestor wifi configurado para iniciar automáticamente (prioridad 1)"
        else
            # Si ya existe, asegurar que conserva la prioridad 1 (después de Plank)
            grep -q '^X-Autostart-Priority=' "$autostart_file" 2>/dev/null || \
                echo "X-Autostart-Priority=1" >> "$autostart_file"
            info "Gestor wifi ya está configurado para iniciar automáticamente"
        fi
    else
        warn "nm-applet no encontrado, no se puede configurar autostart de wifi"
    fi
}
_panel_configurar_almacenamiento_lid() {
    # Configurar comportamiento al cerrar/abrir la tapa
    # Al abrir la tapa, el sistema debe despertarse correctamente
    local logind_conf="/etc/systemd/logind.conf"
    if [ -f "$logind_conf" ]; then
        # Configurar para que al abrir la tapa, el sistema se despierte
        # HandleLidSwitch=suspend (cerrar tapa -> suspender)
        # HandleLidSwitchExternalPower=suspend (cerrar tapa con batería -> suspender)
        # HandleLidSwitchDocked=ignore (cerrar tapa cuando está dockeado -> ignorar)
        local temp_conf="/tmp/logind.conf.tmp"
        if sudo cp "$logind_conf" "$temp_conf" 2>/dev/null; then
            sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' "$temp_conf"
            sudo sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=suspend/' "$temp_conf"
            sudo sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' "$temp_conf"
            sudo sed -i 's/^HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' "$temp_conf"
            sudo sed -i 's/^#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$temp_conf"
            sudo sed -i 's/^HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$temp_conf"
            
            if sudo mv "$temp_conf" "$logind_conf" 2>/dev/null; then
                info "Comportamiento de tapa configurado: al abrir tapa -> despertar"
            else
                warn "No se pudo configurar el comportamiento de la tapa (se requiere sudo)"
            fi
        else
            warn "No se pudo configurar el comportamiento de la tapa (se requiere sudo)"
        fi
    else
        warn "logind.conf no encontrado, no se puede configurar comportamiento de tapa"
    fi
}

_panel_crear_readme() {
    # Crear README con instrucciones de uso del script
    local readme_file="$DIR/README.md"
    
    cat > "$readme_file" << 'READMEEOF'
# Script de Configuración del Panel XFCE

Este script configura automáticamente el panel XFCE, Plank y varias funciones del sistema.

## Opciones de Ejecución

### Ejecutar todo (completo)
```bash
bash panel.sh
```
Configura todo el sistema:
- Panel XFCE con tema macOS
- Plank dock con launchers
- Brave como navegador predeterminado
- Safari usando Brave con icono de Safari
- Gestor wifi al inicio
- Ocultar gestor de llaves de la bandeja

### Opciones individuales
```bash
# Configurar solo el panel XFCE
bash panel.sh config

# Configurar solo Plank
bash panel.sh plank

# Configurar solo el navegador (Safari/Brave)
bash panel.sh navegador

# Desactivar el gestor de llaves
bash panel.sh desactivar-keyring

# Crear copia de seguridad de Plank
bash panel.sh backup

# Reiniciar el panel
bash panel.sh reiniciar
```

## Configuraciones Adicionales

### Configurar comportamiento de la tapa (requiere sudo)
```bash
sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
```

### Configurar arranque silencioso (requiere sudo)
```bash
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 vga=current"/' /etc/default/grub
sudo update-grub
```

## Características

- **Navegador predeterminado**: Brave configurado como navegador del sistema
- **Safari**: Usa Brave internamente pero mantiene icono de Safari
- **Gestor wifi**: Se inicia automáticamente al arranque
- **Gestor de llaves**: Se puede desactivar completamente
- **VirtualBox**: Funciona normalmente (sin agrupado forzado)
- **Plank**: Dock estilo macOS con tema transparente

## Solución de Problemas

Si algo no funciona correctamente:
1. Ejecuta la opción específica para ese componente
2. Verifica que los archivos de configuración se crearon correctamente
3. Reinicia el panel XFCE: `xfce4-panel -r`
4. Reinicia Plank: `pkill plank && plank`

## Archivos Modificados

- `~/.config/xfce4/` - Configuración del panel XFCE
- `~/.config/plank/` - Configuración del dock Plank
- `~/.local/share/applications/` - Launchers modificados
- `~/.local/bin/` - Scripts wrappers si es necesario
READMEEOF
    
    info "README.md creado en $DIR con instrucciones de uso"
}

_panel_desactivar_gestor_llaves() {
    # Desactivar el gestor de llaves (seahorse/gnome-keyring)
    # Evita que funcione el sistema de gestión de contraseñas
    
    # Desactivar servicios de gnome-keyring
    local services=("gnome-keyring-daemon" "gnome-keyring" "seahorse")
    for service in "${services[@]}"; do
        if systemctl --user list-unit-files | grep -q "^$service"; then
            systemctl --user disable "$service" 2>/dev/null || true
            systemctl --user stop "$service" 2>/dev/null || true
            info "Servicio $service desactivado"
        fi
    done
    
    # Desactivar autostart del gestor de llaves
    local autostart_dir="$HOME/.config/autostart"
    if [ -d "$autostart_dir" ]; then
        for keyring_file in "$autostart_dir"/seahorse*.desktop "$autostart_dir"/gnome-keyring*.desktop; do
            if [ -f "$keyring_file" ]; then
                mv "$keyring_file" "$keyring_file.disabled" 2>/dev/null || true
                info "Autostart de gestor de llaves desactivado: $(basename "$keyring_file")"
            fi
        done
    fi
    
    # Desactivar autostart del sistema
    local system_autostart="/etc/xdg/autostart"
    if [ -d "$system_autostart" ]; then
        for keyring_file in "$system_autostart"/seahorse*.desktop "$system_autostart"/gnome-keyring*.desktop; do
            if [ -f "$keyring_file" ]; then
                local local_file="$autostart_dir/$(basename "$keyring_file")"
                mkdir -p "$autostart_dir"
                # Crear override local que desactiva el servicio
                cat > "$local_file" << 'KEYRINGEOF'
[Desktop Entry]
Type=Application
Name=Disabled Keyring
X-GNOME-Autostart-enabled=false
Hidden=true
KEYRINGEOF
                info "Override creado para desactivar: $(basename "$keyring_file")"
            fi
        done
    fi
    
    info "Gestor de llaves desactivado completamente"
}

_panel_arranque_silencioso() {
    # Configurar arranque silencioso - reducir mensajes al inicio
    # Configurar Plymouth para mostrar menos mensajes
    local grub_default="/etc/default/grub"
    if [ -f "$grub_default" ]; then
        local temp_grub="/tmp/grub.tmp"
        if sudo cp "$grub_default" "$temp_grub" 2>/dev/null; then
            # Configurar GRUB para arranque silencioso
            sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 vga=current"/' "$temp_grub"
            sudo sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet loglevel=3"/' "$temp_grub"
            
            if sudo mv "$temp_grub" "$grub_default" 2>/dev/null; then
                info "GRUB configurado para arranque silencioso"
                info "Ejecuta 'sudo update-grub' para aplicar los cambios"
            else
                warn "No se pudo configurar GRUB para arranque silencioso (se requiere sudo)"
            fi
        else
            warn "No se pudo configurar GRUB para arranque silencioso (se requiere sudo)"
        fi
    else
        warn "grub default no encontrado, no se puede configurar arranque silencioso"
    fi
}

_panel_fix_default_browser() {
    # Fija explícitamente el navegador predeterminado del sistema en vez de
    # confiar en que ya esté configurado. Antes, si xdg-settings no devolvía
    # nada, _panel_fix_launcher_safari se cancelaba en silencio (return) y
    # Safari se quedaba sin redirigir a ningún navegador real.
    # Prioridad: Brave > Chrome/Chromium > Firefox > lo primero que haya.
    local candidatos=("brave-browser.desktop" "com.brave.Browser.desktop" \
                       "google-chrome.desktop" "chromium-browser.desktop" "chromium.desktop" \
                       "firefox.desktop" "firefox-esr.desktop")
    local elegido=""
    local c
    for c in "${candidatos[@]}"; do
        if [ -f "/usr/share/applications/$c" ] || [ -f "/usr/local/share/applications/$c" ] || [ -f "$HOME/.local/share/applications/$c" ]; then
            elegido="$c"
            break
        fi
    done
    if [ -z "$elegido" ]; then
        warn "No se encontró Brave/Chrome/Firefox instalado para fijar como predeterminado"
        return 1
    fi
    if command -v xdg-settings &>/dev/null; then
        xdg-settings set default-web-browser "$elegido" 2>/dev/null
    fi
    if command -v xdg-mime &>/dev/null; then
        xdg-mime default "$elegido" text/html x-scheme-handler/http x-scheme-handler/https 2>/dev/null
    fi
    info "Navegador predeterminado fijado a $elegido"
}

_panel_fix_brave_desktop() {
    # Modificar brave-browser.desktop local para que abra como Safari directamente
    local brave_desk="/usr/share/applications/brave-browser.desktop"
    [ -f "$brave_desk" ] || return

    local local_brave="$HOME/.local/share/applications/brave-browser.desktop"
    cp "$brave_desk" "$local_brave"

    # Modificar el comando Exec para usar el wrapper de Safari
    if grep -q '^Exec=' "$local_brave"; then
        sed -i 's|^Exec=/usr/bin/brave-browser-stable %U|Exec='"$HOME"'/.local/bin/safari-browser %U|g' "$local_brave"
        sed -i 's|^Exec=/usr/bin/brave-browser-stable$|Exec='"$HOME"'/.local/bin/safari-browser|g' "$local_brave"
    fi

    # Modificar StartupWMClass a Safari
    if grep -q '^StartupWMClass=' "$local_brave"; then
        sed -i 's|^StartupWMClass=.*|StartupWMClass=Safari|g' "$local_brave"
    else
        sed -i '/^Icon=/a StartupWMClass=Safari' "$local_brave"
    fi

    # Cambiar el nombre a Safari para que Plank lo reconozca como Safari
    if grep -q '^Name=' "$local_brave"; then
        sed -i 's|^Name=Brave Web Browser|Name=Safari|g' "$local_brave"
    fi

    # Cambiar el icono al icono de Safari
    local safari_icon="$HOME/.icons/custom/15_safari.png"
    if [ -f "$safari_icon" ]; then
        if grep -q '^Icon=' "$local_brave"; then
            sed -i "s|^Icon=.*|Icon=$safari_icon|g" "$local_brave"
        else
            sed -i '/^StartupWMClass=/a Icon='$safari_icon'' "$local_brave"
        fi
    fi

    info "Brave configurado para abrir como Safari"
}

_panel_fix_launcher_safari() {
    local safari_desk="$HOME/.local/share/applications/safari.desktop"
    [ -f "$safari_desk" ] || return

    _panel_fix_default_browser

    local default_browser
    default_browser=$(xdg-settings get default-web-browser 2>/dev/null || echo "")
    [ -z "$default_browser" ] && { warn "No hay navegador predeterminado, Safari no se pudo redirigir"; return; }

    local browser_desk=""
    for r in "/usr/share/applications/$default_browser" \
             "/usr/local/share/applications/$default_browser" \
             "$HOME/.local/share/applications/$default_browser"; do
        [ -f "$r" ] && browser_desk="$r" && break
    done
    [ -z "$browser_desk" ] && return

    # ¿El navegador es de base Chromium (Brave, Chrome, Chromium, Edge)?
    # Estos aceptan el flag --class=NOMBRE, que fuerza el WM_CLASS real de
    # la ventana X11 a "Safari" directamente. Es más fiable que copiar el
    # WM_CLASS del navegador y "robarlo" a su .desktop original, porque no
    # depende de qué StartupWMClass (si alguno) trae cada versión instalada.
    local es_chromium=0
    if grep -qiE 'brave|chrome|chromium|edge' <<< "$default_browser"; then
        es_chromium=1
    fi

    # Crear wrapper que ejecuta Brave y cambia su WM_CLASS a Safari directamente
    local wrapper_dir="$HOME/.local/bin"
    local wrapper="$wrapper_dir/safari-browser"
    local browser_bin wrapper_class
    browser_bin=$(grep -oP '(?<=^Exec=)\S+' "$browser_desk" 2>/dev/null | head -1)
    browser_bin="${browser_bin:-/usr/bin/brave-browser-stable}"
    wrapper_class=$(basename "$browser_bin" | sed -E 's/-?(stable|esr|dev|unstable|beta|bin)$//')
    case "$wrapper_class" in
        com.brave.Browser|brave-browser*) wrapper_class="brave-browser" ;;
        google-chrome*)  wrapper_class="google-chrome" ;;
        chromium*)       wrapper_class="chromium" ;;
        microsoft-edge*) wrapper_class="microsoft-edge" ;;
    esac

    mkdir -p "$wrapper_dir"
    cat > "$wrapper" << WRAPPEREOF
#!/bin/bash
# Wrapper: ejecuta el navegador y cambia su WM_CLASS a Safari directamente
${browser_bin} "\$@" &
# Esperar y cambiar WM_CLASS con reintentos
for i in \$(seq 1 15); do
    sleep 0.2
    WINDOW_ID=\$(xdotool search --onlyvisible --class "${wrapper_class}" 2>/dev/null | head -1)
    if [ -n "\$WINDOW_ID" ]; then
        xprop -id "\$WINDOW_ID" -f WM_CLASS 8s -set WM_CLASS "Safari" 2>/dev/null
        break
    fi
done
WRAPPEREOF
    chmod +x "$wrapper"

    # safari.desktop ejecuta el wrapper dinámico (siempre respeta el navegador actual)
    sed -i "s|^Exec=.*|Exec=$wrapper %u|" "$safari_desk"

    # Corregir booleanos mal escritos (Terminal=False en vez de false) que invalidan el .desktop
    sed -i "s|^Terminal=False$|Terminal=false|" "$safari_desk"

    local wm_class
    if [ "$es_chromium" = "1" ]; then
        # El wrapper ya fuerza --class=Safari, así que la clase real es "Safari"
        wm_class="Safari"
    else
        # Navegadores no-Chromium (Firefox, etc.) no soportan --class:
        # recurrimos al método anterior, tomando la clase real del navegador.
        wm_class=$(grep '^StartupWMClass=' "$browser_desk" 2>/dev/null | head -1 | cut -d= -f2-)
        [ -z "$wm_class" ] && wm_class=$(basename "$default_browser" .desktop)
    fi

    if grep -q '^StartupWMClass=' "$safari_desk"; then
        sed -i "s|^StartupWMClass=.*|StartupWMClass=$wm_class|" "$safari_desk"
    else
        sed -i "/^Icon=/a StartupWMClass=$wm_class" "$safari_desk"
    fi

    if [ "$es_chromium" != "1" ]; then
        # Evitar que OTROS lanzadores roben la clase: si un .desktop del sistema reclama la
        # misma StartupWMClass, creamos una copia local SIN esa línea para que el único
        # dueño sea Safari. Solo hace falta con navegadores que no aceptan --class.
        local otros_launcher
        for otros_launcher in /usr/share/applications/*.desktop /usr/local/share/applications/*.desktop; do
            [ -f "$otros_launcher" ] || continue
            grep -q "^StartupWMClass=$wm_class$" "$otros_launcher" || continue
            local otro_nombre otro_destino
            otro_nombre=$(basename "$otros_launcher")
            otro_destino="$HOME/.local/share/applications/$otro_nombre"
            if [ -f "$otro_destino" ] && ! grep -q "^StartupWMClass=$wm_class$" "$otro_destino"; then
                continue
            fi
            sed '/^StartupWMClass=/d' "$otros_launcher" > "$otro_destino"
            info "Override local creado: $otro_nombre (sin StartupWMClass=$wm_class) para que Safari gane"
        done
    fi

    info "Safari redirigido al navegador por defecto via wrapper dinámico (WMClass=$wm_class)"
}

_panel_fix_launcher_photos() {
    local photos_desk="$HOME/.local/share/applications/photos.desktop"
    [ -f "$photos_desk" ] || return
    local ejecutable
    ejecutable=$(grep -oP '(?<=^Exec=)\S+' "$photos_desk" 2>/dev/null || echo "")
    [ -z "$ejecutable" ] && return
    if ! command -v "$ejecutable" &>/dev/null; then
        for cmd in pix xviewer loupe eog shotwell gthumb ristretto gwenview nomacs; do
            if command -v "$cmd" &>/dev/null; then
                sed -i "s|^Exec=.*|Exec=$cmd|" "$photos_desk"
                info "Photos redirigido a $cmd"
                break
            fi
        done
    fi
}

_panel_fix_launcher_notes() {
    local notes_desk="$HOME/.local/share/applications/notes.desktop"
    [ -f "$notes_desk" ] || return
    if grep -q "^Exec=mousepad" "$notes_desk" 2>/dev/null || ! command -v "$(grep -oP '(?<=^Exec=)\S+' "$notes_desk" 2>/dev/null)" &>/dev/null; then
        if command -v sticky &>/dev/null; then
            sed -i 's|^Exec=.*|Exec=sticky|' "$notes_desk"
            info "Notes redirigido a sticky"
        fi
    fi
}

_panel_fix_launcher_settings() {
    local dockitem="$HOME/.config/plank/dock1/launchers/settings.dockitem"
    [ -f "$dockitem" ] || return
    local xfce_settings="xfce4-settings-manager.desktop"
    local found=""
    for r in "/usr/share/applications/$xfce_settings" \
             "/usr/local/share/applications/$xfce_settings" \
             "$HOME/.local/share/applications/$xfce_settings"; do
        [ -f "$r" ] && found="$r" && break
    done
    if [ -z "$found" ]; then
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/$xfce_settings" << 'SETEOF'
[Desktop Entry]
Type=Application
Name=Ajustes
Comment=Configuracion del sistema
Exec=xfce4-settings-manager
Icon=preferences-system
Categories=Settings;X-XFCE;
Terminal=false
SETEOF
        found="$HOME/.local/share/applications/$xfce_settings"
    fi
    printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$found" > "$dockitem"
    info "Launcher 'settings' redirigido a xfce4-settings-manager"
}

_panel_expand_false() {
    local xml="$1"
    [ -f "$xml" ] || return
    sed -i 's|<property name="expand" type="bool" value="true"/>|<property name="expand" type="bool" value="false"/>|g' "$xml"
    sed -i 's|<property name="expand" type="empty"/>|<property name="expand" type="bool" value="false"/>|g' "$xml"
    # También corregir expand vacío en elementos individuales
    sed -i 's|<property name="expand"/>|<property name="expand" type="bool" value="false"/>|g' "$xml"
}

# Asegurar que el ÚLTIMO separador del panel NO se expanda (evita espacio al final)
_panel_last_separator_no_expand() {
    local xml="$1"
    [ -f "$xml" ] || return

    # Obtener IDs de todos los plugins separadores
    local separator_ids
    separator_ids=$(grep -oP '(?<=<property name="plugin-)\d+(?=" type="string" value="separator")' "$xml" | sort -n)
    [ -z "$separator_ids" ] && return

    # El último separador (mayor ID) es típicamente el "end spacer"
    local last_sep_id=$(echo "$separator_ids" | tail -1)

    # Forzar expand=false para ese separador específico
    sed -i "/<property name=\"plugin-${last_sep_id}\" type=\"string\" value=\"separator\">/,/<\/property>/ s|<property name=\"expand\" type=\"bool\" value=\"true\"/>|<property name=\"expand\" type=\"bool\" value=\"false\"/>|g" "$xml"
    sed -i "/<property name=\"plugin-${last_sep_id}\" type=\"string\" value=\"separator\">/,/<\/property>/ s|<property name=\"expand\" type=\"empty\"/>|<property name=\"expand\" type=\"bool\" value=\"false\"/>|g" "$xml"

    # Si no tiene propiedad expand, añadirla
    if ! sed -n "/<property name=\"plugin-${last_sep_id}\" type=\"string\" value=\"separator\">/,/<\/property>/p" "$xml" | grep -q 'name="expand"'; then
        sed -i "/<property name=\"plugin-${last_sep_id}\" type=\"string\" value=\"separator\">/a\\      <property name=\"expand\" type=\"bool\" value=\"false\"/>" "$xml"
    fi

    info "Último separador (plugin-${last_sep_id}) forzado a no expandir"
}

_panel_fix_launcher_add_plank() {
    mkdir -p "$HOME/.icons/custom" "$HOME/.local/bin"
    cat > "$HOME/.icons/custom/dock-add.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#4a9eff"/>
      <stop offset="100%" stop-color="#1a5fcc"/>
    </linearGradient>
  </defs>
  <rect x="4" y="4" width="120" height="120" rx="26" fill="url(#bg)"/>
  <rect x="10" y="10" width="108" height="108" rx="22" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2"/>
  <rect x="40" y="58" width="48" height="12" rx="6" fill="#fff"/>
  <rect x="58" y="40" width="12" height="48" rx="6" fill="#fff"/>
</svg>
SVGEOF

    cat > "$HOME/.local/bin/añadir-plank.sh" << 'SHEOF'
#!/bin/bash
APPS_DIR="/usr/share/applications"
LOCAL_APPS="$HOME/.local/share/applications"
PLANK_DIR="$HOME/.config/plank/dock1/launchers"
APP_LIST=""
for d in "$APPS_DIR" "$LOCAL_APPS"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.desktop; do
        [ -f "$f" ] || continue
        name=""; exec_cmd=""; icon=""; nodisplay=0; terminal=0
        while IFS= read -r line; do
            case "$line" in
                Name=*) name="${line#Name=}" ;;
                Exec=*) exec_cmd="${line#Exec=}" ;;
                Icon=*) icon="${line#Icon=}" ;;
                NoDisplay=true) nodisplay=1 ;;
                Terminal=true) terminal=1 ;;
            esac
        done < "$f"
        [ -z "$name" ] || [ -z "$exec_cmd" ] && continue
        [ "$nodisplay" = "1" ] || [ "$terminal" = "1" ] && continue
        APP_LIST="${APP_LIST}${name}|${exec_cmd}|${icon}\n"
    done
done
CHOICE=$(echo -e "$APP_LIST" | zenity --list --title="Añadir a Plank" --text="Selecciona una aplicación:" --column="Nombre" --column="Comando" --column="Icono" --width=600 --height=500 2>/dev/null)
if [ -z "$CHOICE" ]; then
    RESULT=$(zenity --forms --title="Añadir a Plank" --text="Escribe el comando manualmente:" --add-entry="Comando (ej: /ruta/app --arg)" --add-entry="Nombre" --width=450 2>/dev/null)
    [ -z "$RESULT" ] && exit 0
    CMD=$(echo "$RESULT" | cut -d'|' -f1)
    NAME=$(echo "$RESULT" | cut -d'|' -f2)
    ICON="application-x-executable"
else
    CMD=$(echo "$CHOICE" | cut -d'|' -f2)
    NAME=$(echo "$CHOICE" | cut -d'|' -f1)
    ICON=$(echo "$CHOICE" | cut -d'|' -f3)
fi
[ -z "$CMD" ] && exit 0
[ -z "$NAME" ] && NAME=$(basename "$CMD" | cut -d' ' -f1)
SLUG=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
DESK="$LOCAL_APPS/${SLUG}.desktop"
cat > "$DESK" << DEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$NAME
Exec=$CMD
Terminal=false
Icon=$ICON
Categories=Utility;
DEOF
chmod +x "$DESK"
mkdir -p "$PLANK_DIR"
DOCK="$PLANK_DIR/${SLUG}.dockitem"
cat > "$DOCK" << DEOF
[PlankDockItemPreferences]
Launcher=file://$DESK
DEOF
zenity --info --title="Añadir a Plank" --text="<b>$NAME</b> añadido a Plank" --width=300 2>/dev/null
SHEOF
    chmod +x "$HOME/.local/bin/añadir-plank.sh"

    [ -f "$HOME/.local/bin/añadir-plank.py" ] || cat > "$HOME/.local/bin/añadir-plank.py" << 'PYEOF'
#!/usr/bin/env python3
import os, subprocess, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

APPS_DIR = "/usr/share/applications"
LOCAL_APPS = os.path.expanduser("~/.local/share/applications")
PLANK_DIR = os.path.expanduser("~/.config/plank/dock1/launchers")

def load_icon(name, size=48):
    if not name: return None
    if name.startswith("/"):
        try: return GdkPixbuf.Pixbuf.new_from_file_at_size(name, size, size)
        except: return None
    theme = Gtk.IconTheme.get_default()
    try: return theme.load_icon(name, size, 0)
    except: return None

def get_fallback():
    try: return Gtk.IconTheme.get_default().load_icon("application-x-executable", 48, 0)
    except: return None

def scan_apps():
    apps, seen = [], set()
    fb = get_fallback()
    for d in [APPS_DIR, LOCAL_APPS]:
        if not os.path.isdir(d): continue
        for fname in sorted(os.listdir(d)):
            if not fname.endswith(".desktop") or fname in seen: continue
            seen.add(fname)
            name = exec_cmd = icon = ""; nodisplay = terminal = False
            with open(os.path.join(d, fname), errors="ignore") as f:
                for line in f:
                    if line.startswith("Name="): name = line[5:].strip()
                    elif line.startswith("Exec="): exec_cmd = line[5:].strip()
                    elif line.startswith("Icon="): icon = line[5:].strip()
                    elif line.startswith("NoDisplay=true"): nodisplay = True
                    elif line.startswith("Terminal=true"): terminal = True
            if name and exec_cmd and not nodisplay and not terminal:
                apps.append((name, exec_cmd, icon, load_icon(icon) or fb))
    return apps

class AddWindow(Gtk.Window):
    def __init__(self, apps):
        super().__init__(title="Añadir a Plank")
        self.set_default_size(640, 500)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        try: self.set_type_hint(Gdk.WindowTypeHint.POPUP_MENU)
        except: pass
        self.apps = apps
        self.selected_icon = ""
        self._building = False
        self._flow_items = []

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_start(10); vbox.set_margin_end(10)
        vbox.set_margin_top(10); vbox.set_margin_bottom(10)
        self.add(vbox)

        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Buscar por nombre o comando...")
        self.search.connect("search-changed", self._on_search)
        vbox.pack_start(self.search, False, False, 0)

        self.notebook = Gtk.Notebook()
        vbox.pack_start(self.notebook, True, True, 0)

        sw1 = Gtk.ScrolledWindow()
        self.flow = Gtk.FlowBox()
        self.flow.set_homogeneous(True)
        self.flow.set_column_spacing(6)
        self.flow.set_row_spacing(6)
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        sw1.add(self.flow)
        self.notebook.append_page(sw1, Gtk.Label(label="Iconos"))

        sw2 = Gtk.ScrolledWindow()
        self.liststore = Gtk.ListStore(str, str, str, GdkPixbuf.Pixbuf)
        self.tree = Gtk.TreeView(model=self.liststore)
        r = Gtk.CellRendererPixbuf(); r.set_fixed_size(28, 28)
        self.tree.append_column(Gtk.TreeViewColumn("", r, pixbuf=3))
        t = Gtk.CellRendererText()
        self.tree.append_column(Gtk.TreeViewColumn("Nombre", t, text=0))
        c = Gtk.CellRendererText()
        col = Gtk.TreeViewColumn("Comando", c, text=1); col.set_expand(True)
        self.tree.append_column(col)
        self.tree.get_selection().connect("changed", self._on_tree_sel)
        sw2.add(self.tree)
        self.notebook.append_page(sw2, Gtk.Label(label="Lista"))

        lbl = Gtk.Label(label="O escribe un comando:"); lbl.set_xalign(0)
        vbox.pack_start(lbl, False, False, 0)
        self.entry_cmd = Gtk.Entry()
        self.entry_cmd.set_placeholder_text("ej: /ruta/mi-app --arg")
        vbox.pack_start(self.entry_cmd, False, False, 0)
        lbl2 = Gtk.Label(label="Nombre:"); lbl2.set_xalign(0)
        vbox.pack_start(lbl2, False, False, 0)
        self.entry_name = Gtk.Entry()
        vbox.pack_start(self.entry_name, False, False, 0)

        hbox = Gtk.Box(spacing=8)
        btn_cancel = Gtk.Button(label="Cancelar")
        btn_add = Gtk.Button(label="Añadir")
        btn_add.get_style_context().add_class("suggested-action")
        hbox.pack_end(btn_add, False, False, 0)
        hbox.pack_end(btn_cancel, False, False, 0)
        vbox.pack_start(hbox, False, False, 0)
        btn_cancel.connect("clicked", lambda w: self.destroy())
        btn_add.connect("clicked", self._on_add)
        self.connect("destroy", Gtk.main_quit)

        self._populate("")
        self.show_all()
        GLib.idle_add(self._fix_wmclass)

    def _fix_wmclass(self):
        try:
            xid = self.get_window().get_xid()
            subprocess.run(
                ["xprop", "-id", hex(xid), "-f", "WM_CLASS", "8s",
                 "-set", "WM_CLASS", "añadir-a-plank,Plank"],
                timeout=2
            )
        except Exception:
            pass
        return False

    def _populate(self, q):
        self._building = True
        q = q.lower()
        for child in self.flow.get_children():
            self.flow.remove(child)
        self._flow_items = []
        for name, cmd, icon, pix in self.apps:
            if q and q not in name.lower() and q not in cmd.lower():
                continue
            btn = Gtk.Button()
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            inner.set_margin_start(4); inner.set_margin_end(4)
            inner.set_margin_top(4); inner.set_margin_bottom(4)
            inner.pack_start(Gtk.Image.new_from_pixbuf(pix), False, False, 0)
            lbl = Gtk.Label(label=name)
            lbl.set_ellipsize(3)
            lbl.set_max_width_chars(12)
            lbl.set_xalign(0.5)
            inner.pack_start(lbl, False, False, 0)
            btn.add(inner)
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn._app = (name, cmd, icon)
            btn.connect("clicked", self._on_flow_btn)
            self.flow.add(btn)
            self._flow_items.append((name, cmd, icon))
        self.flow.show_all()
        self.liststore.clear()
        for name, cmd, icon, _ in self.apps:
            if q and q not in name.lower() and q not in cmd.lower():
                continue
            self.liststore.append([name, cmd, icon, load_icon(icon) or get_fallback()])
        self._building = False

    def _on_search(self, entry):
        if not self._building:
            self._populate(entry.get_text())

    def _on_flow_btn(self, btn):
        name, cmd, icon = btn._app
        self.entry_name.set_text(name)
        self.entry_cmd.set_text(cmd)
        self.selected_icon = icon

    def _on_tree_sel(self, sel):
        m, it = sel.get_selected()
        if it:
            self.entry_name.set_text(m.get_value(it, 0))
            self.entry_cmd.set_text(m.get_value(it, 1))
            self.selected_icon = m.get_value(it, 2)

    def _on_add(self, w):
        cmd = self.entry_cmd.get_text().strip()
        name = self.entry_name.get_text().strip()
        icon = self.selected_icon
        if not cmd:
            m, it = self.tree.get_selection().get_selected()
            if it:
                cmd = self.liststore.get_value(it, 1)
                name = name or self.liststore.get_value(it, 0)
                icon = icon or self.liststore.get_value(it, 2)
        if not cmd: return
        if not name: name = os.path.basename(cmd.split()[0])
        slug = name.lower().replace(" ", "-").replace("/", "-")
        desk = os.path.join(LOCAL_APPS, f"{slug}.desktop")
        with open(desk, "w") as f:
            f.write(f"[Desktop Entry]\nVersion=1.0\nType=Application\nName={name}\nExec={cmd}\nTerminal=false\nIcon={icon}\nCategories=Utility;\n")
        os.chmod(desk, 0o755)
        os.makedirs(PLANK_DIR, exist_ok=True)
        with open(os.path.join(PLANK_DIR, f"{slug}.dockitem"), "w") as f:
            f.write(f"[PlankDockItemPreferences]\nLauncher=file://{desk}\n")
        self.destroy()

if __name__ == "__main__":
    AddWindow(scan_apps())
    Gtk.main()
PYEOF
    chmod +x "$HOME/.local/bin/añadir-plank.py"

    # ── Copia de seguridad de Plank: añadir botón directo al diálogo "Añadir a Plank" ──
    local dir_proyecto_backup; dir_proyecto_backup=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [ -f "$dir_proyecto_backup/backup.sh" ]; then
        mkdir -p "$HOME/.local/bin" "$HOME/.icons/custom"
        cp "$dir_proyecto_backup/backup.sh" "$HOME/.local/bin/backup.sh"
        chmod +x "$HOME/.local/bin/backup.sh"
        # El PNG va primero porque hay PCs sin cargador de SVG, y entonces el
        # icono no se pinta o sale borroso en el dock.
        [ -f "$dir_proyecto_backup/icon-plank-backup.svg" ] && \
            cp "$dir_proyecto_backup/icon-plank-backup.svg" "$HOME/.icons/custom/plank-backup.svg"
        if [ -d "$dir_proyecto_backup/iconos" ]; then
            cp -f "$dir_proyecto_backup"/iconos/plank-backup-*.png "$HOME/.icons/custom/" 2>/dev/null
            [ -f "$HOME/.icons/custom/plank-backup-128.png" ] && \
                cp -f "$HOME/.icons/custom/plank-backup-128.png" "$HOME/.icons/custom/plank-backup.png"
        fi

        python3 - << 'PYBACKUP'
import os
p = os.path.expanduser("~/.local/bin/añadir-plank.py")
if not os.path.exists(p):
    raise SystemExit(0)
s = open(p, errors="ignore").read()
if "BACKUP_SCRIPT" not in s:
    s = s.replace(
        'PLANK_DIR = os.path.expanduser("~/.config/plank/dock1/launchers")',
        'PLANK_DIR = os.path.expanduser("~/.config/plank/dock1/launchers")\n'
        'BACKUP_SCRIPT = os.path.expanduser("~/.local/bin/backup.sh")\n'
        'BACKUP_ICON = os.path.expanduser("~/.icons/custom/plank-backup.svg")',
        1)
    s = s.replace(
        "        self._flow_items = []\n        for name, cmd, icon, pix in self.apps:",
        "        self._flow_items = []\n        self._add_backup_button(q)\n        for name, cmd, icon, pix in self.apps:",
        1)
    s = s.replace(
        "    def _on_flow_btn(self, btn):",
        "    def _add_backup_button(self, q=\"\"):\n"
        "        if q and \"respaldo\" not in q:\n            return\n"
        "        try:\n            pix = GdkPixbuf.Pixbuf.new_from_file_at_size(BACKUP_ICON, 48, 48)\n"
        "        except Exception:\n            pix = get_fallback()\n"
        "        btn = Gtk.Button()\n"
        "        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)\n"
        "        inner.set_margin_start(4); inner.set_margin_end(4)\n"
        "        inner.set_margin_top(4); inner.set_margin_bottom(4)\n"
        "        inner.pack_start(Gtk.Image.new_from_pixbuf(pix), False, False, 0)\n"
        "        lbl = Gtk.Label(label=\"Respaldo\")\n"
        "        lbl.set_max_width_chars(12)\n        lbl.set_xalign(0.5)\n"
        "        inner.pack_start(lbl, False, False, 0)\n"
        "        btn.add(inner)\n"
        "        btn.set_relief(Gtk.ReliefStyle.NONE)\n"
        "        btn.connect(\"clicked\", self._on_backup_clicked)\n"
        "        self.flow.add(btn)\n\n"
        "    def _on_backup_clicked(self, w):\n"
        "        if os.path.exists(BACKUP_SCRIPT):\n"
        "            subprocess.Popen([\"bash\", BACKUP_SCRIPT])\n"
        "        self.destroy()\n\n"
        "    def _on_flow_btn(self, btn):",
        1)
    open(p, "w").write(s)
PYBACKUP
        info "Botón de respaldo de Plank añadido al diálogo 'Añadir a Plank'"
    fi

    local desk="$HOME/.local/share/applications/anadir-a-plank.desktop"
    cat > "$desk" << DESKEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Añadir a Plank
Comment=Busca y añade cualquier aplicación al dock de Plank
Exec=python3 $HOME/.local/bin/añadir-plank.py
Terminal=false
Icon=$HOME/.icons/custom/dock-add.svg
Categories=Utility;
DESKEOF
    chmod +x "$desk"

    local dock="$HOME/.config/plank/dock1/launchers/aaa_anadir-a-plank.dockitem"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$desk" > "$dock"

    # Mover al inicio del dock vía dconf
    local cur
    cur=$(dconf read /net/launchpad/plank/docks/dock1/dock-items 2>/dev/null || echo "[]")
    cur=$(echo "$cur" | sed "s/^\[/'aaa_anadir-a-plank.dockitem', /")
    dconf write /net/launchpad/plank/docks/dock1/dock-items "[$cur]" 2>/dev/null || true
    info "Añadir a Plank añadido al dock (primera posición)"
}

panel_plank() {
    step "Configurando Plank"
    pkill -9 plank 2>/dev/null || true
    sleep 1

    local tema_origen="$HOME/ventura-xfce/dock/plank/Ventura"
    local tema_destino="$HOME/.local/share/plank/themes/Ventura"
    mkdir -p "$HOME/.local/share/plank/themes"
    if [ -d "$tema_origen" ]; then
        cp -r "$tema_origen" "$tema_destino"
    else
        mkdir -p "$tema_destino"
        cat > "$tema_destino/dock.theme" << 'EOF'
[PlankTheme]
TopRoundness=4
BottomRoundness=0
LineWidth=1
OuterStrokeColor=40;;40;;40;;180
FillStartColor=255;;255;;255;;25
FillEndColor=255;;255;;255;;25
InnerStrokeColor=255;;255;;255;;35
EOF
        info "Tema Ventura generado manualmente"
    fi

    local trans_destino="$HOME/.local/share/plank/themes/Transparent"
    mkdir -p "$trans_destino"
    cat > "$trans_destino/dock.theme" << 'EOF'
[PlankTheme]
TopRoundness=0
BottomRoundness=0
LineWidth=0
OuterStrokeColor=0;;0;;0;;0
FillStartColor=0;;0;;0;;0
FillEndColor=0;;0;;0;;0
InnerStrokeColor=0;;0;;0;;0
EOF

local lanzadores_origen="$HOME/ventura-xfce/dock/launchers"
    local lanzadores_destino="$HOME/.config/plank/dock1/launchers"
    mkdir -p "$lanzadores_destino"
    local permitidos=("safari" "archivos" "mail" "music" "notes" "photos" "Calc" "pages" "settings" "code")
    for p in "${permitidos[@]}"; do
        rm -f "$lanzadores_destino/${p}.dockitem"
    done
    if [ -d "$lanzadores_origen" ]; then
        for archivo in "$lanzadores_origen"/*.desktop; do
            local base; base=$(basename "$archivo" .desktop)
            local permitido=0
            for p in "${permitidos[@]}"; do
                [ "$p" = "$base" ] && permitido=1 && break
            done
            [ "$permitido" = "0" ] && continue
            local dockitem="$lanzadores_destino/${base}.dockitem"
            local sistema=""
            for ruta in "/usr/share/applications/${base}.desktop" \
                        "/usr/local/share/applications/${base}.desktop" \
                        "$HOME/.local/share/applications/${base}.desktop"; do
                [ -f "$ruta" ] && sistema="$ruta" && break
            done
            if [ -z "$sistema" ]; then
                cp "$archivo" "$HOME/.local/share/applications/${base}.desktop"
                sistema="$HOME/.local/share/applications/${base}.desktop"
            fi
            sed -i "s|lukas|$USER|g; s|ibm-7094a|$USER|g; s|ibm-7094|$USER|g" "$sistema" 2>/dev/null || true
            printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$sistema" > "$dockitem"
        done
        find "$lanzadores_destino" -name "*.dockitem" -exec \
            sed -i "s|/home/lukas/|/home/$USER/|g; s|/home/ibm-7094a/|/home/$USER/|g; s|/home/ibm-7094/|/home/$USER/|g" {} \; 2>/dev/null || true

        _panel_fix_launcher_settings
        _panel_fix_launcher_notes
        _panel_fix_brave_desktop
        _panel_fix_launcher_safari
        _panel_fix_launcher_photos
        _panel_fix_launcher_add_plank
        _panel_fix_launcher_plank_backup

        local cantidad; cantidad=$(ls "$lanzadores_destino"/*.dockitem 2>/dev/null | wc -l)        info "Lanzadores creados: $cantidad"
    else
        warn "Carpeta de lanzadores no encontrada"
    fi

    # ── Asegurar dconf-service para primera ejecución ──
    if ! pgrep -x dconf-service > /dev/null 2>&1; then
        local dconf_bin
        dconf_bin=$(command -v dconf-service || find /usr/lib -name "dconf-service" 2>/dev/null | head -1)
        if [ -n "$dconf_bin" ]; then
            $dconf_bin &
            sleep 1
        fi
    fi

    local dconf_path="/net/launchpad/plank/docks/dock1"
    if command -v dconf &>/dev/null; then
        dconf write "${dconf_path}/theme"          "'Transparent'"
        dconf write "${dconf_path}/position"       "'bottom'"
        dconf write "${dconf_path}/alignment"      "'center'"
        dconf write "${dconf_path}/icon-size"      "48"
        dconf write "${dconf_path}/zoom-enabled"   "true"
        dconf write "${dconf_path}/zoom-percent"   "150"
        dconf write "${dconf_path}/hide-mode"      "'window-dodge'"
        dconf write "${dconf_path}/show-dock-item" "false"
        dconf write "${dconf_path}/lock-items"     "false"
    fi

    info "Plank configurado: Transparente, 48px, zoom 150%"

    setsid nohup plank > /tmp/plank.log 2>&1 &
    sleep 2
    pgrep -x plank > /dev/null && info "Plank corriendo" || warn "Plank no arrancó"
}

_panel_fix_launcher_plank_backup() {
    # El lanzador "Respaldo" lo pone el propio backup.sh con su funcion
    # plank_asegurar_lanzador. Antes esta funcion escribia aqui un .desktop
    # con el nombre viejo "Respaldo de Plank", el icono SVG y un .dockitem
    # llamado plank-backup: por eso el dock acababa con DOS iconos de lo
    # mismo y el que se veia era el que dice "Respaldo de Plank".
    # Delegando, el nombre, el icono y la POSICION en el dock son los del
    # script y no hay nada que se contradiga.
    local dir_proyecto; dir_proyecto=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local instalado="$HOME/.local/bin/backup.sh"
    [ -f "$instalado" ] || instalado="$dir_proyecto/backup.sh"
    if [ ! -f "$instalado" ]; then
        warn "backup.sh no encontrado: no se anade el lanzador 'Respaldo'"
        return
    fi
    chmod +x "$instalado"

    # En una subshell para no soltar variables encima de panel.sh, y sin
    # reiniciar Plank: aqui quien manda sobre Plank es panel_plank.
    (
        source "$instalado" >/dev/null 2>&1 || exit 0
        declare -F plank_asegurar_lanzador >/dev/null 2>&1 || exit 0
        plank_reiniciar() { :; }
        plank_asegurar_lanzador
    ) && info "Lanzador 'Respaldo' anclado en el dock" || warn "No se pudo anclar 'Respaldo' en el dock"
}
panel_configurar() {
    step "Copiando configuración del panel XFCE"
    cp -r ~/ventura-xfce/config/xfce4 ~/.config/
    cp -r ~/ventura-xfce/config/xfce4-dict ~/.config/ 2>/dev/null || true
    chown -R "$USER:$USER" ~/.config/xfce4
    chown -R "$USER:$USER" ~/.config/xfce4-dict 2>/dev/null || true
    find ~/.config/xfce4 -type f -name "*.xml" -exec \
        sed -i "s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true

    find ~/.config/xfce4/panel -name "*.desktop" -exec \
    sed -i "s/lukas/$USER/g; s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true

    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

    # ── ARREGLAR EL XML ───────────────────────────────────────────────────────
    # Todo lo que hay aqui abajo lo hacia antes unaopensource de "sed".
    # Tenian dos fallos:
    #   1. Buscaban "value=.../>" SIN espacio, pero el XML se escribe con
    #      espacio ("value=... />"), asi que no modificaban nada sin dar error.
    #   2. Al corregir eso, insertaban etiquetas sin cerrar. Entonces xfconf
    #      avisaba "el documento termina inesperadamente con elementos todavia
    #      abiertos" y el panel, sin config que leer, arrancaba con la de POR
    #      DEFECTO: solo se veia el menu de aplicaciones.
    # Ademas uno de ellos cambiaba expand=true por false en TODOS los plugins,
    # y por eso la barra de estado no se iba a la derecha de la pantalla.
    # Ahora lo hace arreglo-panel-xml.py, con xml.etree, que siempre devuelve
    # un documento bien cerrado. Si aun asi quedara mal, avisa y no aplica.
    if ! python3 "$DIR/arreglar-panel-xml.py" "$panel_xml"; then
        error "El XML del panel no ha quedado bien formado: no se reinicia nada"
        return 1
    fi
    pkill -9 xfconfd 2>/dev/null || true
    info "Configuración del panel copiada"
    
    # Configurar funciones adicionales
    _panel_autostart_wifi
    _panel_configurar_almacenamiento_lid
    _panel_arranque_silencioso
    
    # Crear README automáticamente
    _panel_crear_readme
}

_panel_remove_right_of_systray() {
    local xml="$1"
    [ -f "$xml" ] || return

    local tmp="/tmp/panel_elim_$$.xml"
    local systray_id=""
    local in_ids=0
    local count=0
    local to_remove=""

    systray_id=$(grep -oP '(?<=<property name="plugin-)\d+(?=" type="string" value="systray")' "$xml" | head -1)
    [ -z "$systray_id" ] && { cp "$xml" "$tmp"; rm -f "$xml"; mv "$tmp" "$xml"; return; }

    while IFS= read -r line; do
        if echo "$line" | grep -q 'plugin-ids.*array'; then
            in_ids=1
            count=0
        fi
        if echo "$line" | grep -q '/property' && [ "$in_ids" -eq 1 ]; then
            in_ids=0
        fi

        if [ "$in_ids" -eq 1 ] && [ "$count" -gt 0 ] && [ "$count" -le 2 ]; then
            local pid=$(echo "$line" | grep -oP 'value="\K\d+(?="/>)')
            if [ -n "$pid" ]; then
                to_remove="$to_remove $pid"
                count=$((count + 1))
                continue
            fi
        fi

        if [ "$in_ids" -eq 1 ]; then
            local curr=$(echo "$line" | grep -oP 'value="\K\d+(?="/>)')
            if [ "$curr" = "$systray_id" ]; then
                count=$((count + 1))
            fi
        fi

        echo "$line" >> "$tmp"
    done < "$xml"

    for pid in $to_remove; do
        sed -i "/<value type=\"int\" value=\"$pid\"\/>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"separator\">/,/<\/property>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"launcher\">/,/<\/property>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"separator\"\/>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"launcher\"\/>/d" "$tmp"
    done

    cp "$tmp" "$xml"
    rm -f "$tmp"
}

# Forzar que el ÚLTIMO separador del panel NO se expanda (evita espacio grande al final)
_panel_last_separator_no_expand() {
    local xml="$1"
    [ -f "$xml" ] || return

    # Encontrar todos los IDs de separadores en el orden del panel
    local separator_ids=()
    local in_ids=0
    while IFS= read -r line; do
        if echo "$line" | grep -q 'plugin-ids.*array'; then
            in_ids=1
            continue
        fi
        if [ "$in_ids" -eq 1 ] && echo "$line" | grep -q '</property>'; then
            in_ids=0
            continue
        fi
        if [ "$in_ids" -eq 1 ]; then
            local pid=$(echo "$line" | grep -oP 'value="\K\d+(?="/>)')
            if [ -n "$pid" ]; then
                # Verificar si este plugin es un separador
                if grep -q "<property name=\"plugin-$pid\" type=\"string\" value=\"separator\"" "$xml"; then
                    separator_ids+=("$pid")
                fi
            fi
        fi
    done < "$xml"

    # El último separador en la lista es el que está al final del panel.
    # No usar ${array[-1]} porque Bash genera "subíndice de matriz incorrecto"
    # cuando la lista está vacía.
    local last_sep_id=""
    if [ "${#separator_ids[@]}" -gt 0 ]; then
        last_sep_id="${separator_ids[${#separator_ids[@]}-1]}"
    fi

    if [ -n "$last_sep_id" ]; then
        # Forzar expand=false para ese separador específico
        sed -i "/<property name=\"plugin-$last_sep_id\" type=\"string\" value=\"separator\">/,/<\/property>/ s|<property name=\"expand\" type=\"bool\" value=\"true\"/>|<property name=\"expand\" type=\"bool\" value=\"false\"/>|g" "$xml"
        sed -i "/<property name=\"plugin-$last_sep_id\" type=\"string\" value=\"separator\">/,/<\/property>/ s|<property name=\"expand\" type=\"empty\"/>|<property name=\"expand\" type=\"bool\" value=\"false\"/>|g" "$xml"
        # Si no tiene propiedad expand, añadirla
        if ! sed -n "/<property name=\"plugin-$last_sep_id\" type=\"string\" value=\"separator\">/,/<\/property>/p" "$xml" | grep -q 'expand'; then
            sed -i "/<property name=\"plugin-$last_sep_id\" type=\"string\" value=\"separator\">/a\\      <property name=\"expand\" type=\"bool\" value=\"false\"/>" "$xml"
        fi
        info "Último separador (plugin-$last_sep_id) forzado a no expandir"
    fi
}

panel_systray_solo_wifi() {
    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$panel_xml" ] || { warn "panel.xml no encontrado"; return; }

    sed -i '/<property name="hidden-legacy-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="hidden-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="known-legacy-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="known-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="hidden-sni-items" type="array">/,/<\/property>/d' "$panel_xml"

    local new_plugin10='    <property name="plugin-10" type="string" value="systray">
      <property name="name-visible" type="bool" value="false"/>
      <property name="square-icons" type="bool" value="false"/>
      <property name="icon-size" type="int" value="0"/>
      <property name="hidden-legacy-items" type="array">
        <value type="string" value="mintupdate.py"/>
        <value type="string" value="tray.py"/>
        <value type="string" value="applet.py"/>
        <value type="string" value="blueman-tray"/>
        <value type="string" value="blueman-applet"/>
        <value type="string" value="blueman applet"/>
        <value type="string" value="Blueman Applet"/>
        <value type="string" value="clipman"/>
        <value type="string" value="seahorse"/>
        <value type="string" value="gnome-keyring"/>
        <value type="string" value="keyring"/>
      </property>
      <property name="hidden-items" type="array">
        <value type="string" value="mintupdate.py"/>
        <value type="string" value="tray.py"/>
        <value type="string" value="applet.py"/>
        <value type="string" value="blueman-tray"/>
        <value type="string" value="blueman-applet"/>
        <value type="string" value="blueman applet"/>
        <value type="string" value="Blueman Applet"/>
        <value type="string" value="clipman"/>
        <value type="string" value="seahorse"/>
        <value type="string" value="gnome-keyring"/>
        <value type="string" value="keyring"/>
      </property>
      <property name="known-legacy-items" type="array">
        <value type="string" value="miniaplicación gestor de la red"/>
      </property>
      <property name="known-items" type="array"/>
    </property>'

    local tmp="/tmp/panel_fix_$$.xml"
    local in_plugin10=0
    local depth=0

    while IFS= read -r line; do
        if echo "$line" | grep -q 'name="plugin-10".*systray'; then
            in_plugin10=1
            depth=0
            echo "$new_plugin10" >> "$tmp"
            continue
        fi

        if [ "$in_plugin10" -eq 1 ]; then
            local opens=$(echo "$line" | grep -c '<property ' || true)
            local scloses=$(echo "$line" | grep -c '/>' || true)
            local closes=$(echo "$line" | grep -c '</property>' || true)
            depth=$((depth + opens - scloses - closes))
            if [ "$depth" -le 0 ] && echo "$line" | grep -q '</property>'; then
                in_plugin10=0
            fi
            continue
        fi

        echo "$line" >> "$tmp"
    done < "$panel_xml"

    cp "$tmp" "$panel_xml"
    rm -f "$tmp"
    info "plugin-10 systray: arrays hidden OK"

    mkdir -p "$HOME/.config/autostart"
    if [ -f /etc/xdg/autostart/blueman.desktop ]; then
        cp -n /etc/xdg/autostart/blueman.desktop "$HOME/.config/autostart/" 2>/dev/null || true
    fi
    grep -q 'Hidden=true' "$HOME/.config/autostart/blueman.desktop" 2>/dev/null || \
        echo "Hidden=true" >> "$HOME/.config/autostart/blueman.desktop"
    # Prioridad 1: Bluetooth arranca justo después de Plank (0)
    grep -q '^X-Autostart-Priority=' "$HOME/.config/autostart/blueman.desktop" 2>/dev/null || \
        echo "X-Autostart-Priority=1" >> "$HOME/.config/autostart/blueman.desktop"

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate          2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true

    local systray_id
    systray_id=$(grep -oP '(?<=<property name="plugin-)\d+(?=" type="string" value="systray")' "$panel_xml" | head -1)
    if [ -n "$systray_id" ]; then
        local base="/plugins/plugin-${systray_id}"
        xfconf-query -c xfce4-panel -p "${base}/hidden-legacy-items" \
            --create --force-array \
            -t string -s "mintupdate.py" \
            -t string -s "tray.py" \
            -t string -s "applet.py" \
            -t string -s "blueman-tray" \
            -t string -s "blueman-applet" \
            -t string -s "blueman applet" \
            -t string -s "Blueman Applet" \
            -t string -s "clipman" \
            2>/dev/null || true
        xfconf-query -c xfce4-panel -p "${base}/hidden-items" \
            --create --force-array \
            -t string -s "mintupdate.py" \
            -t string -s "tray.py" \
            -t string -s "applet.py" \
            -t string -s "blueman-tray" \
            -t string -s "blueman-applet" \
            -t string -s "blueman applet" \
            -t string -s "Blueman Applet" \
            -t string -s "clipman" \
            2>/dev/null || true
        xfconf-query -c xfce4-panel -p "${base}/known-legacy-items" \
            --create --force-array \
            -t string -s "miniaplicación gestor de la red" \
            2>/dev/null || true
        info "Bandeja oculta (array) aplicada en systray plugin-${systray_id}"
    fi

    info "Bandeja: solo wifi visible"
}

_panel_aplicar_colores() {
    # Transparencia del panel superior en % (0 = se ve el fondo de pantalla,
    # 100 = sólido). Cambia con:  PANEL_ALPHA=30 bash panel.sh ...
    local alpha="${PANEL_ALPHA:-0}"
    local color_bg
    local color_fg
    if [ "$MODO" = "dark" ]; then
        color_bg="#2b2b2b"
        color_fg="#ffffff"
    else
        color_bg="#f6f6f6"
        color_fg="#000000"
    fi

    local panel_ids
    panel_ids=$(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oP '/panels/panel-\d+$' | sort -u)
    for pid in $panel_ids; do
        xfconf-query -c xfce4-panel -p "$pid/background-style" --create -t int -s 1 2>/dev/null || \
            xfconf-query -c xfce4-panel -p "$pid/background-style" -s 1 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "$pid/background-color" --create -t string -s "$color_bg" 2>/dev/null || \
            xfconf-query -c xfce4-panel -p "$pid/background-color" -s "$color_bg" 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "$pid/fg-color" --create -t string -s "$color_fg" 2>/dev/null || \
            xfconf-query -c xfce4-panel -p "$pid/fg-color" -s "$color_fg" 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "$pid/background-alpha" --create -t int -s "$alpha" 2>/dev/null || \
            xfconf-query -c xfce4-panel -p "$pid/background-alpha" -s "$alpha" 2>/dev/null || true
        # Paneles nuevos (4.14+) usan background-rgba (r,g,b,a en 0..1)
        local rgb_c a_dec
        [ "$MODO" = "dark" ] && rgb_c="0.169" || rgb_c="0.965"
        a_dec=$(awk -v a="$alpha" 'BEGIN{printf "%.2f", a/100}')
        xfconf-query -c xfce4-panel -p "$pid/background-rgba" --create --force-array \
            -t double -s "$rgb_c" -t double -s "$rgb_c" -t double -s "$rgb_c" -t double -s "$a_dec" 2>/dev/null || true
    done

    local xml_panel="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    if [ -f "$xml_panel" ]; then
        if grep -q 'background-style' "$xml_panel"; then
            sed -i "s|<property name=\"background-style\" type=\"int\" value=\"[0-9]*\"/>|<property name=\"background-style\" type=\"int\" value=\"1\"/>|g" "$xml_panel"
        fi
        if grep -q 'background-color' "$xml_panel"; then
            sed -i "s|<property name=\"background-color\" type=\"string\" value=\"[^\"]*\"/>|<property name=\"background-color\" type=\"string\" value=\"$color_bg\"/>|g" "$xml_panel"
        else
            sed -i "/<property name=\"background-style\"/a\\      <property name=\"background-color\" type=\"string\" value=\"$color_bg\"/>" "$xml_panel"
        fi
        if grep -q 'fg-color' "$xml_panel"; then
            sed -i "s|<property name=\"fg-color\" type=\"string\" value=\"[^\"]*\"/>|<property name=\"fg-color\" type=\"string\" value=\"$color_fg\"/>|g" "$xml_panel"
        else
            sed -i "/<property name=\"background-color\"/a\\      <property name=\"fg-color\" type=\"string\" value=\"$color_fg\"/>" "$xml_panel"
        fi
        if grep -q 'background-alpha' "$xml_panel"; then
            sed -i "s|<property name=\"background-alpha\" type=\"int\" value=\"[0-9]*\"/>|<property name=\"background-alpha\" type=\"int\" value=\"$alpha\"/>|g" "$xml_panel"
        fi
    fi

    info "Colores del panel aplicados (modo $MODO, transparencia: alpha=$alpha%)"
}

panel_reiniciar() {
    local iconos="$1"; local tema_gtk="$2"; local tema_xfwm="$3"
    pkill -15 xfce4-panel 2>/dev/null || true; sleep 1
    pkill -9  xfce4-panel 2>/dev/null || true
    for i in $(seq 1 8); do pgrep -x xfce4-panel > /dev/null || break; sleep 1; done
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    rm -rf ~/.cache/xfce4 ~/.cache/sessions
    rm -f  /tmp/xfce4-panel-*.pid 2>/dev/null || true
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/xfce4-panel"* 2>/dev/null || true
    asegurar_xfconfd; sleep 2

    xfconf-query -c xsettings -p /Net/ThemeName       -s "$tema_gtk"   || true
    xfconf-query -c xsettings -p /Net/IconThemeName   -s "$iconos"     || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "WhiteSur-cursors" || true
    xfconf-query -c xsettings -p /Gtk/FontName        -s "Inter 11"    || true
    xfconf-query -c xfwm4 -p /general/theme           -s "$tema_xfwm"  || true
    xfconf-query -c xfwm4 -p /general/button_layout   -s "CMH|"        || true

    aplicar_iconos_persistente "$iconos"
    [ "$MODO" = "dark" ] && aplicar_modo_oscuro
    gtk-update-icon-cache -f -t "$HOME/.icons/$iconos" 2>/dev/null || true

    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    cp ~/ventura-xfce/config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml "$panel_xml"
    # Ver el comentario de panel_configurar: los sed de aqui estaban rotos y
    # dejaban el XML sin cerrar, y el panel se caia a la config por defecto.
    # Ahora lo hace arreglo-panel-xml.py, que siempre devuelve XML bien formado.
    if ! python3 "$DIR/arreglar-panel-xml.py" "$panel_xml"; then
        error "El XML del panel no ha quedado bien formado: no se reinicia nada"
        return 1
    fi
    if [ -d ~/ventura-xfce/config/xfce4/panel ]; then
        cp -r ~/ventura-xfce/config/xfce4/panel/launcher-* ~/.config/xfce4/panel/ 2>/dev/null || true
        find ~/.config/xfce4/panel -name "*.desktop" -exec \
            sed -i "s/lukas/$USER/g; s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true
        local n_launchers
        n_launchers=$(ls -d ~/.config/xfce4/panel/launcher-* 2>/dev/null | wc -l)
        info "Launchers del panel restaurados: $n_launchers"
    else
        warn "Carpeta de launchers del repo no encontrada — los iconos del panel pueden faltar"
    fi
    grep -q 'reserve-space' "$panel_xml" 2>/dev/null || \
        sed -i '/<property name="position-locked" type="bool" value="true"\/>/a\      <property name="reserve-space" type="bool" value="true"/>' "$panel_xml"
    # OJO: panel_systray_solo_wifi y _panel_last_separator_no_expand ya NO se
    # llaman aqui. Las dos tocan el XML con "sed" y lo dejaban mal cerrado
    # (por eso el panel se caia a la config por defecto y solo salia el menu
    # de aplicaciones). Todo eso lo hace ahora arreglo-panel-xml.py, que ademas
    # comprueba que el XML siga siendo valido antes de escribirlo.
    _panel_aplicar_colores
    asegurar_xfconfd

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate          2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true
    sleep 1

    DISPLAY="${DISPLAY:-:0}" setsid nohup xfce4-panel >/dev/null 2>&1 & sleep 4
    if ! pgrep -x xfce4-panel > /dev/null; then
        DISPLAY="${DISPLAY:-:0}" setsid nohup xfce4-panel >/dev/null 2>&1 & sleep 3
    fi
    pgrep -x xfce4-panel > /dev/null && info "Panel reiniciado" || warn "El panel no arrancó"
    # Antes aqui habia un bucle de 3 vueltas que mataba xfconfd, llamaba a
    # panel_systray_solo_wifi y tiraba otra vez de este "sed":
    #     s|expand" type="bool" value="true"|...value="false"|g
    # Osea que ponia a false el expand de TODOS los plugins, incluido el
    # separador que tiene que empujar la barra de estado a la derecha. Por eso
    # el wifi y el volumen no se veian pegados al borde derecho de la pantalla.
    # Ahora el XML se arregla una sola vez, con python3, y se comprueba.
    asegurar_xfconfd
    python3 "$DIR/arreglar-panel-xml.py" "$panel_xml" || \
        warn "El XML del panel no ha quedado bien formado"
    sleep 2
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    pkill -15 xfce4-panel 2>/dev/null || true; sleep 2
    pkill -9  xfce4-panel 2>/dev/null || true
    for i in $(seq 1 8); do pgrep -x xfce4-panel > /dev/null || break; sleep 1; done
    asegurar_xfconfd
    DISPLAY="${DISPLAY:-:0}" setsid nohup xfce4-panel >/dev/null 2>&1 & sleep 3

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true

    pkill -9 xfdesktop 2>/dev/null || true; sleep 2
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$iconos" || true
    aplicar_iconos_persistente "$iconos"

    local xml_escritorio="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    if [ -f "$xml_escritorio" ]; then
        local fondo; fondo=$(grep -oP '(?<=value=")[^"]+\.(jpg|png|jpeg|webp)(?=")' "$xml_escritorio" | head -1)
        if [ -n "$fondo" ] && [ -s "$fondo" ]; then
            for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|last-single-image|image-path"); do
                xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" --create -t string 2>/dev/null || true
            done
        fi
    fi
    sleep 2; DISPLAY="${DISPLAY:-:0}" setsid nohup xfdesktop >/dev/null 2>&1 & sleep 2
    sleep 3
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    # Este era el ultimo sitio donde se rompia el panel: ponia a false el
    # expand de TODOS los plugins, y con ello la barra de estado (wifi, volumen,
    # bateria) dejaba de estar pegada al borde derecho. Se pasa elXML por el
    # reparador, que solo toca el separador que tiene que empujar.
    python3 "$DIR/arreglar-panel-xml.py" "$panel_xml" || \
        warn "El XML del panel no ha quedado bien formado"
    asegurar_xfconfd
    info "Panel y escritorio reiniciados"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! _panel_asegurar_repositorio; then
        error "No se puede continuar sin el repositorio ventura-xfce en $HOME/ventura-xfce"
    fi

    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; TEMA_XFWM="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; TEMA_XFWM="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA TEMA_XFWM ICONOS

    paso="${2:-todo}"
    case "$paso" in
        config|configurar)    panel_configurar ;;
        plank)     panel_plank ;;
        backup)    _panel_fix_launcher_plank_backup ;;
        navegador)  _panel_fix_brave_desktop; _panel_fix_launcher_safari ;;
        desactivar-keyring) _panel_desactivar_gestor_llaves ;;
        reiniciar) panel_reiniciar "$ICONOS" "$TEMA" "$TEMA_XFWM" ;;
        todo)
            panel_configurar
            panel_plank
            panel_reiniciar "$ICONOS" "$TEMA" "$TEMA_XFWM"
            ;;
    esac
fi
