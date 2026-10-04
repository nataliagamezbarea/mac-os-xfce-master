#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

nautilus_configurar() {
    step "Configurando Nautilus"
    apt_silencioso install nautilus
    mkdir -p ~/.local/share/applications

    local ejecutar_nautilus="env GTK_THEME=$TEMA GTK_CSD=1 nautilus %U"
    # Categories=FileManager es necesario para que Firefox lo encuentre via D-Bus
    printf '[Desktop Entry]\nType=Application\nName=Archivos\nExec=%s\nIcon=org.gnome.Nautilus\nMimeType=inode/directory;x-directory/normal;application/x-gnome-saved-search;x-scheme-handler/file;\nStartupNotify=true\nCategories=FileManager;\n' \
        "$ejecutar_nautilus" > ~/.local/share/applications/org.gnome.Nautilus.desktop

    rm -f ~/.local/share/applications/thunar.desktop
    rm -f ~/.local/share/applications/Thunar-folder-handler.desktop

    mkdir -p ~/.config/xfce4
    echo "FileManager=nautilus" > ~/.config/xfce4/helpers.rc
    if command -v exo-preferred-applications &>/dev/null; then
        exo-preferred-applications --file-manager nautilus 2>/dev/null || true
    fi

    # Escribir mimeapps.list en AMBAS rutas:
    # - ~/.config/mimeapps.list  → la que leen GIO, GLib y Firefox
    # - ~/.local/share/applications/mimeapps.list → la que lee xdg-mime legacy
    # xdg-mime y gio solo escriben en una de las dos; lo hacemos directamente
    # para garantizar que ambas queden correctas.
    _escribir_mimeapps() {
        local destino="$1"
        mkdir -p "$(dirname "$destino")"
        # Si ya existe, eliminar entradas antiguas de otros gestores y de Nautilus
        if [ -f "$destino" ]; then
            sed -i '/^inode\/directory=/d'                        "$destino"
            sed -i '/^x-directory\/normal=/d'                     "$destino"
            sed -i '/^application\/x-gnome-saved-search=/d'       "$destino"
            sed -i '/^x-scheme-handler\/file=/d'                   "$destino"
        fi
        # Asegurarse de que existe la sección [Default Applications]
        if ! grep -q '^\[Default Applications\]' "$destino" 2>/dev/null; then
            printf '\n[Default Applications]\n' >> "$destino"
        fi
        # Insertar justo después de la cabecera de sección
        sed -i '/^\[Default Applications\]/a inode\/directory=org.gnome.Nautilus.desktop\nx-directory\/normal=org.gnome.Nautilus.desktop\napplication\/x-gnome-saved-search=org.gnome.Nautilus.desktop\nx-scheme-handler\/file=org.gnome.Nautilus.desktop' \
            "$destino"
    }
    _escribir_mimeapps "$HOME/.config/mimeapps.list"
    _escribir_mimeapps "$HOME/.local/share/applications/mimeapps.list"

    # Sincronizar también con GIO (por si acaso)
    if command -v gio &>/dev/null; then
        gio mime inode/directory org.gnome.Nautilus.desktop 2>/dev/null || true
        gio mime x-directory/normal org.gnome.Nautilus.desktop 2>/dev/null || true
        gio mime application/x-gnome-saved-search org.gnome.Nautilus.desktop 2>/dev/null || true
        gio mime x-scheme-handler/file org.gnome.Nautilus.desktop 2>/dev/null || true
    fi

    pkill -9 exo-helper 2>/dev/null || true

    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    cat > ~/.config/gtk-3.0/settings.ini << GTKEOF
[Settings]
gtk-theme-name=$TEMA
gtk-icon-theme-name=$ICONOS
gtk-cursor-theme-name=WhiteSur-cursors
gtk-font-name=Inter 11
gtk-decoration-layout=close,minimize,maximize:
gtk-application-prefer-dark-theme=1
GTKEOF

    cat > ~/.config/gtk-4.0/settings.ini << GTKEOF
[Settings]
gtk-theme-name=$TEMA
gtk-icon-theme-name=$ICONOS
gtk-cursor-theme-name=WhiteSur-cursors
gtk-font-name=Inter 11
gtk-decoration-layout=close,minimize,maximize:
gtk-application-prefer-dark-theme=1
GTKEOF

    local origen_gtk4=""
    for candidato in "$HOME/.themes/$TEMA/gtk-4.0" "/usr/share/themes/$TEMA/gtk-4.0"; do
        [ -d "$candidato" ] && origen_gtk4="$candidato" && break
    done
    if [ -n "$origen_gtk4" ]; then
        [ -f "$origen_gtk4/gtk.gresource" ] && cp "$origen_gtk4/gtk.gresource" ~/.config/gtk-4.0/ || true
        cat > ~/.config/gtk-4.0/gtk.css << CSSEOF
@import url("file://${origen_gtk4}/gtk.css");
CSSEOF
        cat > ~/.config/gtk-4.0/gtk-dark.css << CSSEOF
@import url("file://${origen_gtk4}/gtk-dark.css");
CSSEOF
    fi

    # cups-browsed roba el nombre D-Bus org.freedesktop.FileManager1
    # y Firefox lo usa para abrir carpetas. cups-browsed no implementa
    # ShowFolders, entonces Firefox cree que funciona pero no abre nada.
    if systemctl is-active cups-browsed &>/dev/null 2>&1; then
        sudo systemctl stop cups-browsed 2>/dev/null || true
        sudo systemctl disable cups-browsed 2>/dev/null || true
        info "cups-browsed detenido (ocupaba org.freedesktop.FileManager1)"
    fi

    # Thunar --daemon también reclama org.freedesktop.FileManager1 al arrancar.
    # Si Thunar llega primero (lo normal en XFCE), Firefox usa Thunar en vez de Nautilus.
    # Solución: deshabilitar el servicio D-Bus de Thunar para que Nautilus sea el único.
    if [ -f /usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service ]; then
        sudo mv /usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service \
                /usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service.disabled 2>/dev/null || true
        info "Thunar FileManager1 deshabilitado (servicio D-Bus)"
    fi
    # Registrar Nautilus como servicio D-Bus para org.freedesktop.FileManager1
    # Sin esto, Firefox no puede abrir carpetas si Nautilus no está en autostart.
    mkdir -p ~/.local/share/dbus-1/services
    cat > ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service << DBUSEOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=/usr/bin/env GTK_THEME=$TEMA GTK_CSD=1 /usr/bin/nautilus --gapplication-service
DBUSEOF

    # Detener thunar.service si systemd lo tiene activo (evita que lo respawnée)
    systemctl --user stop thunar.service 2>/dev/null || true
    thunar -q 2>/dev/null || true
    pkill -9 Thunar 2>/dev/null || true
    sleep 1
    # Prevenir que Thunar arranque como daemon en el autostart
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/thunar-daemon.desktop << 'THUNAREOF'
[Desktop Entry]
Type=Application
Name=Thunar Daemon
Exec=thunar --daemon
Hidden=true
X-GNOME-Autostart-enabled=false
THUNAREOF

    # Crear wrapper para abrir carpetas con Nautilus
    # Esto asegura que Firefox (y cualquier app) abra Nautilus aunque el
    # daemon D-Bus no esté corriendo aún. Se usa para GIO/mimeapps, NO para
    # el helper de XFCE (ver más abajo, ahí el formato es distinto).
    local nautilus_handler="$HOME/.local/bin/nautilus-folder-handler"
    mkdir -p "$HOME/.local/bin"
    cat > "$nautilus_handler" << WRAPEOF
#!/bin/bash
export GTK_CSD=1
export GTK_THEME=$TEMA
if ! pgrep -u "$USER" nautilus > /dev/null 2>&1; then
    (nohup nautilus --new-window > /dev/null 2>&1 &)
fi
exec nautilus --new-window "\$@"
WRAPEOF
    chmod +x "$nautilus_handler"

    # ── Registrar Nautilus como "helper" oficial de XFCE (exo) ─────────
    # IMPORTANTE: helpers.rc NO acepta una ruta literal en "FileManager=".
    # Exo busca un ID que coincida con un .desktop en xfce4/helpers/ (formato
    # X-XFCE-Helper, con X-XFCE-Binaries en vez de Exec=). Si el ID no
    # resuelve a ningún helper, exo cae al fallback por defecto: Thunar.
    # Esto es justo lo que rompía "abrir carpeta" en el escritorio: el script
    # ponía la ruta completa del wrapper como ID, que nunca resuelve.
    apt_silencioso install xfce4-helpers 2>/dev/null || true
    mkdir -p ~/.local/share/xfce4/helpers
    cat > ~/.local/share/xfce4/helpers/nautilus.desktop << 'HELPEREOF'
[Desktop Entry]
Version=1.0
Icon=org.gnome.Nautilus
Type=X-XFCE-Helper
Name=Nautilus
StartupNotify=true
X-XFCE-Binaries=nautilus;
X-XFCE-Category=FileManager
X-XFCE-Commands=%B;
X-XFCE-CommandsWithParameter=%B "%s";
HELPEREOF

    mkdir -p ~/.config/xfce4
    if grep -q '^TerminalEmulator=' ~/.config/xfce4/helpers.rc 2>/dev/null; then
        local term_emu; term_emu=$(grep '^TerminalEmulator=' ~/.config/xfce4/helpers.rc)
        echo "FileManager=nautilus" > ~/.config/xfce4/helpers.rc
        echo "$term_emu" >> ~/.config/xfce4/helpers.rc
    else
        echo "FileManager=nautilus" > ~/.config/xfce4/helpers.rc
    fi
    # Añadir ~/.local/bin al PATH del helper
    grep -q 'local/bin' ~/.profile 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
    export PATH="$HOME/.local/bin:$PATH"

    # También crear un .desktop que use el wrapper (con ruta completa)
    # Categories=FileManager es imprescindible para que Firefox lo registre como
    # gestor de archivos vía D-Bus org.freedesktop.FileManager1
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/nautilus-folder-handler.desktop << DESKEOF
[Desktop Entry]
Type=Application
Name=Nautilus (handler)
Exec=$HOME/.local/bin/nautilus-folder-handler %U
Icon=org.gnome.Nautilus
MimeType=inode/directory;x-directory/normal;x-scheme-handler/file;
NoDisplay=true
Categories=FileManager;
DESKEOF

    # Forzar asociación MIME con el wrapper en AMBOS mimeapps.list
    # (mismo helper que ya usamos arriba, ahora apuntando al handler)
    _escribir_mimeapps_handler() {
        local destino="$1"
        mkdir -p "$(dirname "$destino")"
        if [ -f "$destino" ]; then
            sed -i '/^inode\/directory=/d'          "$destino"
            sed -i '/^x-directory\/normal=/d'        "$destino"
            sed -i '/^x-scheme-handler\/file=/d'     "$destino"
        fi
        if ! grep -q '^\[Default Applications\]' "$destino" 2>/dev/null; then
            printf '\n[Default Applications]\n' >> "$destino"
        fi
        sed -i '/^\[Default Applications\]/a inode\/directory=nautilus-folder-handler.desktop\nx-directory\/normal=nautilus-folder-handler.desktop\nx-scheme-handler\/file=nautilus-folder-handler.desktop' \
            "$destino"
    }
    _escribir_mimeapps_handler "$HOME/.config/mimeapps.list"
    _escribir_mimeapps_handler "$HOME/.local/share/applications/mimeapps.list"

    if command -v gio &>/dev/null; then
        gio mime inode/directory nautilus-folder-handler.desktop 2>/dev/null || true
        gio mime x-directory/normal nautilus-folder-handler.desktop 2>/dev/null || true
        gio mime x-scheme-handler/file nautilus-folder-handler.desktop 2>/dev/null || true
    fi

    apt_silencioso install xdg-utils exo-utils 2>/dev/null || true

    # Actualizar la base de datos de .desktop para que XFCE/exo encuentre Nautilus
    # como "gestor de archivos preferido" en exo-preferred-applications
    update-desktop-database ~/.local/share/applications 2>/dev/null || true

    # Autostart: arrancar Nautilus como daemon D-Bus al inicio de sesión
    # Sin esto Firefox no puede llamar ShowItems (botón "Abrir carpeta" en descargas)
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/nautilus-daemon.desktop << NAUTEOF
[Desktop Entry]
Type=Application
Name=Nautilus (daemon D-Bus)
Exec=bash -c "GTK_THEME=$TEMA GTK_CSD=1 nautilus --gapplication-service"
Hidden=true
StartupNotify=false
X-GNOME-Autostart-enabled=false
NAUTEOF

    [ "$MODO" = "dark" ] && aplicar_modo_oscuro
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s false 2>/dev/null || true

    # Forzar decoraciones macOS en Nautilus (CSD con botones a la izquierda)
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
    if command -v dconf &>/dev/null; then
        dconf write /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'" 2>/dev/null || true
    fi
    gsettings set org.gnome.nautilus.window-state side-panel-width 220 2>/dev/null || true

    info "Nautilus configurado como gestor de archivos"
}


# ── Parche de la extensión ─────────────────────────────────────────
# La extensión upstream ignora las claves "icon" y "tip" del config.json y construye
# el Nautilus.MenuItem solo con name+label. En Nautilus >= 43 los elementos propios del
# menú contextual sí llevan icono, así que GTK reserva la columna de iconos y todas las
# entradas de la extensión se dibujaban con un hueco en blanco delante.
# Además update_config() conservaba la lista de acciones anterior cuando el config.json
# faltaba o estaba corrupto, de modo que la caché del menú podía servir entradas de una
# configuración vieja (lo que salía solo al principio, nada más instalar).
# Es idempotente: se reaplica en cada instalación sin romper nada.
nautilus_extension_parche() {
    local parche
    parche="$(mktemp /tmp/afn-parche-XXXXXX.py)"
    cat > "$parche" << 'PATCHEOF'
#!/usr/bin/env python3
# Parche de Actions for Nautilus.
#
# 1) Las claves "icon" y "tip" del config.json nunca se leian: _create_command_menu_item
#    construia el Nautilus.MenuItem solo con name+label. En Nautilus >= 43 los elementos
#    propios del menu contextual llevan icono, asi que GTK reserva la columna de iconos
#    y todas las entradas de la extension se dibujaban con un hueco en blanco delante
#    ("bug de espacios en blanco"). Nautilus.MenuItem si tiene las propiedades icon/tip.
# 2) update_config() dejaba self.actions con la lista anterior cuando el config.json
#    no existia o estaba corrupto, de modo que la cache del menu podia servir entradas
#    de una configuracion vieja (lo que aparecia solo al principio, tras instalar).
#
# Idempotente: se puede reaplicar en cada instalacion sin romper nada.
import os
import py_compile
import sys

EXT_DIR = "/usr/local/share/nautilus-python/extensions"

PARCHES = [
    ("afn_config.py", [
        (
            'class CommandAction():\n    def __init__(self):\n        self.label  = ""\n',
            'class CommandAction():\n    def __init__(self):\n        self.label  = ""\n'
            '        self.icon   = ""\n        self.tip    = ""\n',
            "CommandAction: campos icon/tip",
        ),
        (
            'class MenuAction():\n    def __init__(self):\n        self.label  = ""\n        self.sort = True\n',
            'class MenuAction():\n    def __init__(self):\n        self.label  = ""\n'
            '        self.icon   = ""\n        self.sort = True\n',
            "MenuAction: campo icon",
        ),
        (
            '    action.label = json_action["label"].strip() if type(json_action.get("label", "")) == str else ""\n'
            '    action.sort = json_action.get("sort", "manual") == "auto"\n',
            '    action.label = json_action["label"].strip() if type(json_action.get("label", "")) == str else ""\n'
            '    action.icon = json_action.get("icon", "").strip() if type(json_action.get("icon", "")) == str else ""\n'
            '    action.sort = json_action.get("sort", "manual") == "auto"\n',
            "_check_menu_action: leer icon",
        ),
        (
            '    action.command_line = json_action["command_line"].strip() if "command_line" in json_action and isinstance(json_action["command_line"], str) else ""\n',
            '    action.icon = json_action.get("icon", "").strip() if type(json_action.get("icon", "")) == str else ""\n'
            '    action.tip = json_action.get("tip", "").strip() if type(json_action.get("tip", "")) == str else ""\n'
            '    action.command_line = json_action["command_line"].strip() if "command_line" in json_action and isinstance(json_action["command_line"], str) else ""\n',
            "_check_command_action: leer icon/tip",
        ),
        (
            '            else:\n'
            '                logger.warning(f"Config file {_config_path} does not exist. Extension will not display any menu items until a config file is created.")\n'
            '        except Exception as e:\n'
            '            logger.error("Config file " + _config_path + " load failed", exc_info=e)\n',
            '            else:\n'
            '                logger.warning(f"Config file {_config_path} does not exist. Extension will not display any menu items until a config file is created.")\n'
            '                # Sin fichero no se arrastran las acciones de la configuracion anterior\n'
            '                self.reset_config()\n'
            '        except Exception as e:\n'
            '            logger.error("Config file " + _config_path + " load failed", exc_info=e)\n'
            '            # Un config roto no debe dejar el menu anterior colgado\n'
            '            self.actions = []\n',
            "update_config: descartar acciones obsoletas",
        ),
    ]),
    ("afn_menu.py", [
        (
            '        menu_item = Nautilus.MenuItem(\n'
            '            name="Actions4Nautilus: :Menu" + action.idString + group,\n'
            '            label=action.label,\n'
            '        )\n',
            '        menu_item = Nautilus.MenuItem(\n'
            '            name="Actions4Nautilus: :Menu" + action.idString + group,\n'
            '            label=action.label,\n'
            '            icon=action.icon or None,\n'
            '        )\n',
            "submenu: pasar icono",
        ),
        (
            '    menu_item = Nautilus.MenuItem(name=name, label=label)\n',
            '    menu_item = Nautilus.MenuItem(name=name, label=label,\n'
            '                                  icon=action.icon or None,\n'
            '                                  tip=action.tip or None)\n',
            "entrada de comando: pasar icono y tip",
        ),
    ]),
]


def main():
    applied, already, fallidos = [], [], []

    for nombre, cambios in PARCHES:
        ruta = os.path.join(EXT_DIR, nombre)
        if not os.path.isfile(ruta):
            fallidos.append("%s: no existe" % nombre)
            continue
        with open(ruta) as f:
            texto = f.read()
        original = texto
        for viejo, nuevo, etiqueta in cambios:
            if nuevo in texto:
                already.append("%s: %s" % (nombre, etiqueta))
            elif viejo in texto:
                texto = texto.replace(viejo, nuevo, 1)
                applied.append("%s: %s" % (nombre, etiqueta))
            else:
                # upstream cambiado: no se rompe la instalacion, solo se avisa
                fallidos.append("%s: %s" % (nombre, etiqueta))
        if texto != original:
            with open(ruta, "w") as f:
                f.write(texto)
            os.chmod(ruta, 0o644)

    if fallidos:
        for a in applied:
            print("  aplicado    %s" % a)
        for a in fallidos:
            print("  NO ENCONTRADO %s" % a)
        print("  parche incompleto: %d cambios, %d sin aplicar" % (len(applied), len(fallidos)))
        return 2

    # comprobacion de sintaxis de lo escrito
    for nombre, _ in PARCHES:
        ruta = os.path.join(EXT_DIR, nombre)
        if os.path.isfile(ruta):
            try:
                py_compile.compile(ruta, cfile="/tmp/.afn-check.pyc", doraise=True)
            except py_compile.PyCompileError as e:
                print("  error de sintaxis en %s: %s" % (nombre, e))
                return 3

    for a in applied:
        print("  aplicado    %s" % a)
    for a in already:
        print("  ya estaba   %s" % a)
    print("  %d cambios, %d ya presentes" % (len(applied), len(already)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PATCHEOF
    if sudo python3 "$parche"; then
        info "Extensión parcheada: los menús contextuales salen con icono"
    else
        warn "No se pudo parchear la extensión; el menú contextual seguirá sin iconos"
    fi
    rm -f "$parche"
}

nautilus_extension_menu() {
    step "Instalando gestor de menú contextual (Actions for Nautilus)"

    # ── Dependencias ────────────────────────────────────────────
    apt_silencioso install python3-nautilus python3-gi procps xclip 2>/dev/null || true

    # ── Instalar extensión Actions for Nautilus ────────────────
    local EXT_DIR="/usr/local/share/nautilus-python/extensions"
    sudo rm -rf "$EXT_DIR/actions-for-nautilus" 2>/dev/null || true
    if [ ! -f "$EXT_DIR/actions_for_nautilus.py" ]; then
        info "Descargando extensión Actions for Nautilus..."
        if [ -d "$HOME/actions-for-nautilus" ]; then
            rm -rf "$HOME/actions-for-nautilus"
        fi
        git -C "$HOME" clone --depth 1 "https://github.com/bassmanitram/actions-for-nautilus.git"
        sudo mkdir -p "$EXT_DIR"
        sudo cp "$HOME/actions-for-nautilus/extensions/actions-for-nautilus"/*.py "$EXT_DIR/"
        rm -rf "$HOME/actions-for-nautilus"
        info "Extensión Actions for Nautilus instalada"
    else
        info "Extensión Actions for Nautilus ya instalada"
    fi

    # El upstream no lee los iconos del config.json: se parchea siempre
    nautilus_extension_parche

    local cfg_dir="$HOME/.local/share/actions-for-nautilus"
    mkdir -p "$cfg_dir"

    # ── gestor.py: CRUD GTK ─────────────────────────────────
    cat > "$cfg_dir/gestor.py" << 'PYEOF'
#!/usr/bin/env python3
import json, os, sys, re, subprocess, locale
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf, GLib

CONFIG_PATH = os.path.expanduser("~/.local/share/actions-for-nautilus/config.json")

_i18n = {
    "es": {
        "gestor_title": "Gestor de Acciones - Nautilus",
        "btn_add": "Añadir", "btn_edit": "Editar", "btn_delete": "Eliminar",
        "btn_up": "Subir", "btn_down": "Bajar", "btn_close": "Cerrar",
        "btn_save": "Guardar", "btn_cancel": "Cancelar",
        "btn_select": "Seleccionar", "btn_browse": "Examinar",
        "col_label": "Label", "col_type": "Tipo", "col_command": "Comando",
        "status_sel_first": "Selecciona una acción primero",
        "status_added": "añadida", "status_updated": "actualizada",
        "status_deleted": "eliminada",
        "status_empty_label": "El label no puede estar vacío",
        "confirm_delete": "Eliminar", "confirm_title": "Confirmar",
        "dlg_add": "Añadir acción", "dlg_edit": "Editar acción",
        "dlg_browser_title": "Seleccionar aplicación",
        "search_placeholder": "Buscar aplicación...",
        "lbl_label": "Label:", "lbl_command": "Comando:",
        "lbl_type": "Tipo:", "lbl_appears": "Aparece en:",
        "lbl_cwd": "CWD:", "lbl_icon": "Icono:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Carpetas / espacio vacío",
        "ft_files": "Archivos", "ft_both": "Carpetas y archivos",
        "cwd_placeholder": "%d, %f, o vacío",
        "icon_none": "(ninguno)", "chk_shell": "Usar shell",
        "suffix_menu": "  [menu]",
    },
    "en": {
        "gestor_title": "Actions Manager - Nautilus",
        "btn_add": "Add", "btn_edit": "Edit", "btn_delete": "Delete",
        "btn_up": "Up", "btn_down": "Down", "btn_close": "Close",
        "btn_save": "Save", "btn_cancel": "Cancel",
        "btn_select": "Select", "btn_browse": "Browse",
        "col_label": "Label", "col_type": "Type", "col_command": "Command",
        "status_sel_first": "Select an action first",
        "status_added": "added", "status_updated": "updated",
        "status_deleted": "deleted",
        "status_empty_label": "Label cannot be empty",
        "confirm_delete": "Delete", "confirm_title": "Confirm",
        "dlg_add": "Add action", "dlg_edit": "Edit action",
        "dlg_browser_title": "Select application",
        "search_placeholder": "Search application...",
        "lbl_label": "Label:", "lbl_command": "Command:",
        "lbl_type": "Type:", "lbl_appears": "Appears on:",
        "lbl_cwd": "CWD:", "lbl_icon": "Icon:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Folders / empty space",
        "ft_files": "Files", "ft_both": "Folders and files",
        "cwd_placeholder": "%d, %f, or empty",
        "icon_none": "(none)", "chk_shell": "Use shell",
        "suffix_menu": "  [menu]",
    },
    "fr": {
        "gestor_title": "Gestionnaire d'actions - Nautilus",
        "btn_add": "Ajouter", "btn_edit": "Modifier", "btn_delete": "Supprimer",
        "btn_up": "Monter", "btn_down": "Descendre", "btn_close": "Fermer",
        "btn_save": "Enregistrer", "btn_cancel": "Annuler",
        "btn_select": "Sélectionner", "btn_browse": "Parcourir",
        "col_label": "Label", "col_type": "Type", "col_command": "Commande",
        "status_sel_first": "Sélectionnez d'abord une action",
        "status_added": "ajoutée", "status_updated": "modifiée",
        "status_deleted": "supprimée",
        "status_empty_label": "Le label ne peut pas être vide",
        "confirm_delete": "Supprimer", "confirm_title": "Confirmer",
        "dlg_add": "Ajouter une action", "dlg_edit": "Modifier l'action",
        "dlg_browser_title": "Choisir une application",
        "search_placeholder": "Rechercher une application...",
        "lbl_label": "Label:", "lbl_command": "Commande:",
        "lbl_type": "Type:", "lbl_appears": "Apparaît sur:",
        "lbl_cwd": "CWD:", "lbl_icon": "Icône:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Dossiers / espace vide",
        "ft_files": "Fichiers", "ft_both": "Dossiers et fichiers",
        "cwd_placeholder": "%d, %f, ou vide",
        "icon_none": "(aucun)", "chk_shell": "Utiliser le shell",
        "suffix_menu": "  [menu]",
    },
    "de": {
        "gestor_title": "Aktionsverwaltung - Nautilus",
        "btn_add": "Hinzufügen", "btn_edit": "Bearbeiten", "btn_delete": "Löschen",
        "btn_up": "Hoch", "btn_down": "Runter", "btn_close": "Schließen",
        "btn_save": "Speichern", "btn_cancel": "Abbrechen",
        "btn_select": "Auswählen", "btn_browse": "Durchsuchen",
        "col_label": "Label", "col_type": "Typ", "col_command": "Befehl",
        "status_sel_first": "Wähle zuerst eine Aktion",
        "status_added": "hinzugefügt", "status_updated": "aktualisiert",
        "status_deleted": "gelöscht",
        "status_empty_label": "Label darf nicht leer sein",
        "confirm_delete": "Löschen", "confirm_title": "Bestätigen",
        "dlg_add": "Aktion hinzufügen", "dlg_edit": "Aktion bearbeiten",
        "dlg_browser_title": "Anwendung auswählen",
        "search_placeholder": "Anwendung suchen...",
        "lbl_label": "Label:", "lbl_command": "Befehl:",
        "lbl_type": "Typ:", "lbl_appears": "Erscheint auf:",
        "lbl_cwd": "CWD:", "lbl_icon": "Symbol:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Ordner / leerer Raum",
        "ft_files": "Dateien", "ft_both": "Ordner und Dateien",
        "cwd_placeholder": "%d, %f, oder leer",
        "icon_none": "(keines)", "chk_shell": "Shell verwenden",
        "suffix_menu": "  [menu]",
    },
    "it": {
        "gestor_title": "Gestore Azioni - Nautilus",
        "btn_add": "Aggiungi", "btn_edit": "Modifica", "btn_delete": "Elimina",
        "btn_up": "Su", "btn_down": "Giù", "btn_close": "Chiudi",
        "btn_save": "Salva", "btn_cancel": "Annulla",
        "btn_select": "Seleziona", "btn_browse": "Sfoglia",
        "col_label": "Label", "col_type": "Tipo", "col_command": "Comando",
        "status_sel_first": "Seleziona prima un'azione",
        "status_added": "aggiunta", "status_updated": "aggiornata",
        "status_deleted": "eliminata",
        "status_empty_label": "Il label non può essere vuoto",
        "confirm_delete": "Elimina", "confirm_title": "Conferma",
        "dlg_add": "Aggiungi azione", "dlg_edit": "Modifica azione",
        "dlg_browser_title": "Seleziona applicazione",
        "search_placeholder": "Cerca applicazione...",
        "lbl_label": "Label:", "lbl_command": "Comando:",
        "lbl_type": "Tipo:", "lbl_appears": "Appare su:",
        "lbl_cwd": "CWD:", "lbl_icon": "Icona:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Cartelle / spazio vuoto",
        "ft_files": "File", "ft_both": "Cartelle e file",
        "cwd_placeholder": "%d, %f, o vuoto",
        "icon_none": "(nessuna)", "chk_shell": "Usa shell",
        "suffix_menu": "  [menu]",
    },
    "pt": {
        "gestor_title": "Gestor de Ações - Nautilus",
        "btn_add": "Adicionar", "btn_edit": "Editar", "btn_delete": "Excluir",
        "btn_up": "Subir", "btn_down": "Descer", "btn_close": "Fechar",
        "btn_save": "Salvar", "btn_cancel": "Cancelar",
        "btn_select": "Selecionar", "btn_browse": "Procurar",
        "col_label": "Label", "col_type": "Tipo", "col_command": "Comando",
        "status_sel_first": "Selecione uma ação primeiro",
        "status_added": "adicionada", "status_updated": "atualizada",
        "status_deleted": "excluída",
        "status_empty_label": "O label não pode estar vazio",
        "confirm_delete": "Excluir", "confirm_title": "Confirmar",
        "dlg_add": "Adicionar ação", "dlg_edit": "Editar ação",
        "dlg_browser_title": "Selecionar aplicativo",
        "search_placeholder": "Buscar aplicativo...",
        "lbl_label": "Label:", "lbl_command": "Comando:",
        "lbl_type": "Tipo:", "lbl_appears": "Aparece em:",
        "lbl_cwd": "CWD:", "lbl_icon": "Ícone:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Pastas / espaço vazio",
        "ft_files": "Arquivos", "ft_both": "Pastas e arquivos",
        "cwd_placeholder": "%d, %f, ou vazio",
        "icon_none": "(nenhum)", "chk_shell": "Usar shell",
        "suffix_menu": "  [menu]",
    },
    "nl": {
        "gestor_title": "Actiebeheer - Nautilus",
        "btn_add": "Toevoegen", "btn_edit": "Bewerken", "btn_delete": "Verwijderen",
        "btn_up": "Omhoog", "btn_down": "Omlaag", "btn_close": "Sluiten",
        "btn_save": "Opslaan", "btn_cancel": "Annuleren",
        "btn_select": "Selecteren", "btn_browse": "Bladeren",
        "col_label": "Label", "col_type": "Type", "col_command": "Opdracht",
        "status_sel_first": "Selecteer eerst een actie",
        "status_added": "toegevoegd", "status_updated": "bijgewerkt",
        "status_deleted": "verwijderd",
        "status_empty_label": "Label mag niet leeg zijn",
        "confirm_delete": "Verwijderen", "confirm_title": "Bevestigen",
        "dlg_add": "Actie toevoegen", "dlg_edit": "Actie bewerken",
        "dlg_browser_title": "Applicatie selecteren",
        "search_placeholder": "Applicatie zoeken...",
        "lbl_label": "Label:", "lbl_command": "Opdracht:",
        "lbl_type": "Type:", "lbl_appears": "Verschijnt op:",
        "lbl_cwd": "CWD:", "lbl_icon": "Pictogram:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Mappen / lege ruimte",
        "ft_files": "Bestanden", "ft_both": "Mappen en bestanden",
        "cwd_placeholder": "%d, %f, of leeg",
        "icon_none": "(geen)", "chk_shell": "Shell gebruiken",
        "suffix_menu": "  [menu]",
    },
    "ru": {
        "gestor_title": "Менеджер действий - Nautilus",
        "btn_add": "Добавить", "btn_edit": "Изменить", "btn_delete": "Удалить",
        "btn_up": "Вверх", "btn_down": "Вниз", "btn_close": "Закрыть",
        "btn_save": "Сохранить", "btn_cancel": "Отмена",
        "btn_select": "Выбрать", "btn_browse": "Обзор",
        "col_label": "Метка", "col_type": "Тип", "col_command": "Команда",
        "status_sel_first": "Сначала выберите действие",
        "status_added": "добавлено", "status_updated": "обновлено",
        "status_deleted": "удалено",
        "status_empty_label": "Метка не может быть пустой",
        "confirm_delete": "Удалить", "confirm_title": "Подтверждение",
        "dlg_add": "Добавить действие", "dlg_edit": "Изменить действие",
        "dlg_browser_title": "Выберите приложение",
        "search_placeholder": "Поиск приложения...",
        "lbl_label": "Метка:", "lbl_command": "Команда:",
        "lbl_type": "Тип:", "lbl_appears": "Появляется на:",
        "lbl_cwd": "CWD:", "lbl_icon": "Иконка:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "Папки / пустое место",
        "ft_files": "Файлы", "ft_both": "Папки и файлы",
        "cwd_placeholder": "%d, %f, или пусто",
        "icon_none": "(нет)", "chk_shell": "Использовать shell",
        "suffix_menu": "  [menu]",
    },
    "zh": {
        "gestor_title": "操作管理器 - Nautilus",
        "btn_add": "添加", "btn_edit": "编辑", "btn_delete": "删除",
        "btn_up": "上移", "btn_down": "下移", "btn_close": "关闭",
        "btn_save": "保存", "btn_cancel": "取消",
        "btn_select": "选择", "btn_browse": "浏览",
        "col_label": "标签", "col_type": "类型", "col_command": "命令",
        "status_sel_first": "请先选择一个操作",
        "status_added": "已添加", "status_updated": "已更新",
        "status_deleted": "已删除",
        "status_empty_label": "标签不能为空",
        "confirm_delete": "删除", "confirm_title": "确认",
        "dlg_add": "添加操作", "dlg_edit": "编辑操作",
        "dlg_browser_title": "选择应用程序",
        "search_placeholder": "搜索应用程序...",
        "lbl_label": "标签:", "lbl_command": "命令:",
        "lbl_type": "类型:", "lbl_appears": "出现在:",
        "lbl_cwd": "CWD:", "lbl_icon": "图标:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "文件夹 / 空白区域",
        "ft_files": "文件", "ft_both": "文件夹和文件",
        "cwd_placeholder": "%d, %f, 或留空",
        "icon_none": "(无)", "chk_shell": "使用 shell",
        "suffix_menu": "  [菜单]",
    },
    "ja": {
        "gestor_title": "アクション管理 - Nautilus",
        "btn_add": "追加", "btn_edit": "編集", "btn_delete": "削除",
        "btn_up": "上へ", "btn_down": "下へ", "btn_close": "閉じる",
        "btn_save": "保存", "btn_cancel": "キャンセル",
        "btn_select": "選択", "btn_browse": "参照",
        "col_label": "ラベル", "col_type": "種類", "col_command": "コマンド",
        "status_sel_first": "最初にアクションを選択してください",
        "status_added": "追加されました", "status_updated": "更新されました",
        "status_deleted": "削除されました",
        "status_empty_label": "ラベルは空にできません",
        "confirm_delete": "削除", "confirm_title": "確認",
        "dlg_add": "アクションを追加", "dlg_edit": "アクションを編集",
        "dlg_browser_title": "アプリケーションを選択",
        "search_placeholder": "アプリケーションを検索...",
        "lbl_label": "ラベル:", "lbl_command": "コマンド:",
        "lbl_type": "種類:", "lbl_appears": "表示場所:",
        "lbl_cwd": "CWD:", "lbl_icon": "アイコン:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "フォルダ / 空きスペース",
        "ft_files": "ファイル", "ft_both": "フォルダとファイル",
        "cwd_placeholder": "%d, %f, または空",
        "icon_none": "(なし)", "chk_shell": "シェルを使用",
        "suffix_menu": "  [メニュー]",
    },
    "ko": {
        "gestor_title": "작업 관리자 - Nautilus",
        "btn_add": "추가", "btn_edit": "편집", "btn_delete": "삭제",
        "btn_up": "위로", "btn_down": "아래로", "btn_close": "닫기",
        "btn_save": "저장", "btn_cancel": "취소",
        "btn_select": "선택", "btn_browse": "찾아보기",
        "col_label": "레이블", "col_type": "유형", "col_command": "명령",
        "status_sel_first": "먼저 작업을 선택하세요",
        "status_added": "추가됨", "status_updated": "업데이트됨",
        "status_deleted": "삭제됨",
        "status_empty_label": "레이블은 비울 수 없습니다",
        "confirm_delete": "삭제", "confirm_title": "확인",
        "dlg_add": "작업 추가", "dlg_edit": "작업 편집",
        "dlg_browser_title": "응용 프로그램 선택",
        "search_placeholder": "응용 프로그램 검색...",
        "lbl_label": "레이블:", "lbl_command": "명령:",
        "lbl_type": "유형:", "lbl_appears": "표시 위치:",
        "lbl_cwd": "CWD:", "lbl_icon": "아이콘:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "폴더 / 빈 공간",
        "ft_files": "파일", "ft_both": "폴더 및 파일",
        "cwd_placeholder": "%d, %f, 또는 비움",
        "icon_none": "(없음)", "chk_shell": "쉘 사용",
        "suffix_menu": "  [메뉴]",
    },
    "ar": {
        "gestor_title": "مدير الإجراءات - نوتيلوس",
        "btn_add": "إضافة", "btn_edit": "تعديل", "btn_delete": "حذف",
        "btn_up": "أعلى", "btn_down": "أسفل", "btn_close": "إغلاق",
        "btn_save": "حفظ", "btn_cancel": "إلغاء",
        "btn_select": "اختيار", "btn_browse": "تصفح",
        "col_label": "تسمية", "col_type": "نوع", "col_command": "أمر",
        "status_sel_first": "اختر إجراء أولاً",
        "status_added": "تمت الإضافة", "status_updated": "تم التحديث",
        "status_deleted": "تم الحذف",
        "status_empty_label": "لا يمكن أن تكون التسمية فارغة",
        "confirm_delete": "حذف", "confirm_title": "تأكيد",
        "dlg_add": "إضافة إجراء", "dlg_edit": "تعديل الإجراء",
        "dlg_browser_title": "اختر تطبيقًا",
        "search_placeholder": "بحث عن تطبيق...",
        "lbl_label": "تسمية:", "lbl_command": "أمر:",
        "lbl_type": "نوع:", "lbl_appears": "يظهر على:",
        "lbl_cwd": "CWD:", "lbl_icon": "أيقونة:",
        "opt_cmd": "command", "opt_menu": "menu",
        "ft_dirs": "مجلدات / مساحة فارغة",
        "ft_files": "ملفات", "ft_both": "مجلدات وملفات",
        "cwd_placeholder": "%d, %f, أو فارغ",
        "icon_none": "(لا شيء)", "chk_shell": "استخدام شل",
        "suffix_menu": "  [قائمة]",
    },
}

_lang_code = "en"
try:
    lc, _ = locale.getdefaultlocale()
    if lc:
        for code in _i18n:
            if lc.startswith(code) or lc.startswith(code.split("_")[0]):
                _lang_code = code
                break
except:
    pass

def _(key):
    return _i18n.get(_lang_code, _i18n["en"]).get(key, _i18n["en"].get(key, key))

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"actions": [], "sort": "manual", "debug": False}

def save_config(config):
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)
    refresh_nautilus()

def refresh_nautilus():
    subprocess.Popen(["nautilus", "-q"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def load_icon(icon_name, size=32):
    if not icon_name:
        return None
    try:
        theme = Gtk.IconTheme.get_default()
        if theme.has_icon(icon_name):
            return theme.load_icon(icon_name, size, 0)
    except:
        pass
    if os.path.isfile(icon_name):
        try:
            return GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, size, size)
        except:
            pass
    return None

FALLBACK_ICON = None
def get_fallback_icon(size=32):
    global FALLBACK_ICON
    if FALLBACK_ICON is None:
        try:
            theme = Gtk.IconTheme.get_default()
            FALLBACK_ICON = theme.load_icon("application-x-executable", size, 0)
        except:
            pass
    return FALLBACK_ICON

def icon_button(icon_name, tooltip=""):
    btn = Gtk.Button.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON)
    if tooltip:
        btn.set_tooltip_text(tooltip)
    return btn

def scan_apps():
    apps = []
    seen_bins = set()
    desktop_dirs = [
        os.path.expanduser("~/.local/share/applications"),
        "/usr/share/applications",
        "/usr/local/share/applications",
    ]
    for d in desktop_dirs:
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if not fname.endswith(".desktop"):
                continue
            path = os.path.join(d, fname)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    content = fh.read()
            except:
                continue
            name = ""
            exec_cmd = ""
            icon = ""
            nodisplay = False
            terminal = False
            for line in content.splitlines():
                raw = line
                if raw.startswith("Name="):
                    name = raw[5:].strip()
                elif raw.startswith("Exec="):
                    exec_cmd = raw[5:].strip()
                    exec_cmd = re.sub(r'%[uUfFdDnNickvm]', "", exec_cmd).strip()
                    exec_cmd = re.sub(r'\s+', " ", exec_cmd)
                elif raw.startswith("Icon="):
                    icon = raw[5:].strip()
                elif raw.startswith("NoDisplay="):
                    nodisplay = raw[10:].strip() == "true"
                elif raw.startswith("Terminal="):
                    terminal = raw[9:].strip() == "true"
            if name and exec_cmd and not nodisplay and not terminal:
                binary = exec_cmd.split()[0] if exec_cmd.split() else ""
                bin_base = os.path.basename(binary)
                pixbuf = load_icon(icon) or get_fallback_icon()
                apps.append((name, exec_cmd, icon, bin_base, True, pixbuf))
                if bin_base:
                    seen_bins.add(bin_base)
    bin_dirs = ["/usr/bin", "/usr/local/bin", os.path.expanduser("~/.local/bin")]
    blacklist = {
        "cp", "mv", "ls", "rm", "mkdir", "rmdir", "touch", "cat", "grep",
        "sed", "awk", "find", "xargs", "sort", "uniq", "wc", "head", "tail",
        "cut", "tr", "diff", "patch", "tar", "gzip", "gunzip", "bzip2",
        "xz", "zip", "unzip", "chmod", "chown", "chgrp", "ps", "top",
        "htop", "kill", "pkill", "pgrep", "df", "du", "mount", "umount",
        "fdisk", "mkfs", "ssh", "scp", "ping", "traceroute", "wget", "curl",
        "python", "python3", "perl", "ruby", "lua", "php", "node", "npm",
        "cargo", "rustc", "go", "gcc", "g++", "clang", "make", "cmake",
        "git", "svn", "hg", "docker", "systemctl", "journalctl", "apt",
        "apt-get", "dpkg", "pacman", "yum", "dnf", "flatpak", "snap",
        "alias", "bg", "fg", "jobs", "cd", "pwd", "echo", "printf",
        "read", "test", "eval", "exec", "exit", "export", "type", "hash",
        "help", "set", "unset", "shopt", "bind", "true", "false",
        "sleep", "timeout", "yes", "seq", "expr", "let", "source",
        "killall", "pidof", "nmtui", "nmcli", "ip", "ifconfig",
        "route", "arp", "netstat", "ss", "iwconfig", "iw", "rfkill",
        "bluetoothctl", "fsck", "blkid", "lsblk", "parted",
    }
    fb = get_fallback_icon()
    for d in bin_dirs:
        if not os.path.isdir(d):
            continue
        try:
            for fname in sorted(os.listdir(d)):
                if fname in seen_bins or fname in blacklist or len(fname) < 3:
                    continue
                if fname.startswith(".") or fname.startswith("_"):
                    continue
                path = os.path.join(d, fname)
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    apps.append((fname, fname + " %F", "", fname, False, fb))
        except:
            pass
    return apps

class AppBrowser(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(title=_("dlg_browser_title"), transient_for=parent,
                         modal=True, destroy_with_parent=True)
        self.set_default_size(650, 500)
        self.selected_app = None
        box = self.get_content_area()
        box.set_spacing(6)
        box.set_margin_start(8); box.set_margin_end(8)
        box.set_margin_top(8); box.set_margin_bottom(8)
        self.entry_search = Gtk.SearchEntry()
        self.entry_search.set_placeholder_text(_("search_placeholder"))
        box.pack_start(self.entry_search, False, False, 0)
        self.store = Gtk.ListStore(str, str, GdkPixbuf.Pixbuf, str)
        self.treeview = Gtk.TreeView(model=self.store)
        self.treeview.set_headers_visible(True)
        pix_rend = Gtk.CellRendererPixbuf()
        pix_rend.set_fixed_size(36, 36)
        col_icon = Gtk.TreeViewColumn("", pix_rend, pixbuf=2)
        col_icon.set_min_width(40)
        self.treeview.append_column(col_icon)
        rend = Gtk.CellRendererText()
        col_name = Gtk.TreeViewColumn(_("col_label"), rend, text=0)
        col_name.set_resizable(True); col_name.set_min_width(200); col_name.set_sort_column_id(0)
        self.treeview.append_column(col_name)
        rend2 = Gtk.CellRendererText()
        col_cmd = Gtk.TreeViewColumn(_("col_command"), rend2, text=1)
        col_cmd.set_resizable(True); col_cmd.set_expand(True)
        self.treeview.append_column(col_cmd)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.add(self.treeview)
        box.pack_start(scrolled, True, True, 0)
        hbox = Gtk.Box(spacing=6)
        btn_sel = icon_button("emblem-default", _("btn_select"))
        btn_sel.get_style_context().add_class("suggested-action")
        btn_cancel = icon_button("window-close", _("btn_cancel"))
        hbox.pack_end(btn_sel, False, False, 0); hbox.pack_end(btn_cancel, False, False, 0)
        box.pack_start(hbox, False, False, 0)
        self.apps = scan_apps()
        self._populate("")
        self.entry_search.connect("search-changed", self._on_search)
        self.treeview.connect("row-activated", lambda tv, p, c: self._select())
        btn_sel.connect("clicked", lambda w: self._select())
        btn_cancel.connect("clicked", lambda w: self.destroy())
        self.show_all()
    def _populate(self, query):
        self.store.clear()
        q = query.lower().strip()
        for name, cmd, icon, binary, has_icon, pixbuf in self.apps:
            if q and q not in name.lower() and q not in cmd.lower() and q not in binary:
                continue
            self.store.append([name, cmd, pixbuf, icon])
    def _on_search(self, entry):
        self._populate(entry.get_text())
    def _select(self):
        sel = self.treeview.get_selection()
        m, it = sel.get_selected()
        if it is None: return
        name = m.get_value(it, 0)
        cmd = m.get_value(it, 1)
        icon_name = m.get_value(it, 3)
        self.selected_app = (name, cmd, icon_name)
        self.response(Gtk.ResponseType.OK)

class FormDialog(Gtk.Dialog):
    def __init__(self, parent, action=None):
        title = _("dlg_add") if action is None else _("dlg_edit")
        super().__init__(title=title, transient_for=parent, modal=True, destroy_with_parent=True)
        self.set_default_size(520, 450)
        self.add_button(_("btn_cancel"), Gtk.ResponseType.CANCEL)
        self.add_button(_("btn_save"), Gtk.ResponseType.OK)
        self.icon_name = ""
        box = self.get_content_area()
        box.set_spacing(8)
        box.set_margin_start(12); box.set_margin_end(12)
        box.set_margin_top(12); box.set_margin_bottom(12)
        grid = Gtk.Grid(column_spacing=8, row_spacing=8)
        grid.attach(Gtk.Label(label=_("lbl_label"), xalign=1), 0, 0, 1, 1)
        self.entry_label = Gtk.Entry(); grid.attach(self.entry_label, 1, 0, 2, 1)
        grid.attach(Gtk.Label(label=_("lbl_command"), xalign=1), 0, 1, 1, 1)
        hbox_cmd = Gtk.Box(spacing=4)
        self.entry_cmd = Gtk.Entry(); hbox_cmd.pack_start(self.entry_cmd, True, True, 0)
        btn_browse = icon_button("system-search", _("btn_browse")); hbox_cmd.pack_start(btn_browse, False, False, 0)
        grid.attach(hbox_cmd, 1, 1, 2, 1)
        grid.attach(Gtk.Label(label=_("lbl_type"), xalign=1), 0, 2, 1, 1)
        self.combo_type = Gtk.ComboBoxText()
        self.combo_type.append_text(_("opt_cmd")); self.combo_type.append_text(_("opt_menu"))
        self.combo_type.set_active(0); grid.attach(self.combo_type, 1, 2, 2, 1)
        grid.attach(Gtk.Label(label=_("lbl_appears"), xalign=1), 0, 3, 1, 1)
        self.combo_ft = Gtk.ComboBoxText()
        self.combo_ft.append_text(_("ft_dirs"))
        self.combo_ft.append_text(_("ft_files"))
        self.combo_ft.append_text(_("ft_both"))
        self.combo_ft.set_active(0); grid.attach(self.combo_ft, 1, 3, 2, 1)
        grid.attach(Gtk.Label(label=_("lbl_cwd"), xalign=1), 0, 4, 1, 1)
        self.entry_cwd = Gtk.Entry()
        self.entry_cwd.set_placeholder_text(_("cwd_placeholder"))
        grid.attach(self.entry_cwd, 1, 4, 2, 1)
        grid.attach(Gtk.Label(label=_("lbl_icon"), xalign=1), 0, 5, 1, 1)
        hbox_icon = Gtk.Box(spacing=6)
        self.icon_image = Gtk.Image()
        self.icon_image.set_from_pixbuf(get_fallback_icon(24))
        self.icon_label = Gtk.Label(label=_("icon_none"))
        self.icon_label.set_xalign(0)
        hbox_icon.pack_start(self.icon_image, False, False, 0)
        hbox_icon.pack_start(self.icon_label, True, True, 0)
        grid.attach(hbox_icon, 1, 5, 2, 1)
        hbox = Gtk.Box(spacing=12)
        self.check_shell = Gtk.CheckButton(label=_("chk_shell"))
        hbox.pack_start(self.check_shell, False, False, 0)
        box.pack_start(grid, False, False, 0); box.pack_start(hbox, False, False, 0)
        if action:
            self.entry_label.set_text(action.get("label", ""))
            self.entry_cmd.set_text(action.get("command_line", ""))
            tp = action.get("type", "command")
            self.combo_type.set_active(0 if tp == "command" else 1)
            ft = action.get("filetypes", [])
            if "directory" in ft and "file" in ft: self.combo_ft.set_active(2)
            elif "file" in ft: self.combo_ft.set_active(1)
            else: self.combo_ft.set_active(0)
            self.entry_cwd.set_text(action.get("cwd", ""))
            self.check_shell.set_active(action.get("use_shell", False))
            self.icon_name = action.get("icon", "")
            self._update_icon_preview()
        btn_browse.connect("clicked", self._on_browse)
        self.show_all()
    def _update_icon_preview(self):
        pixbuf = load_icon(self.icon_name, 24)
        label = self.icon_name or _("icon_none")
        if pixbuf:
            self.icon_image.set_from_pixbuf(pixbuf)
        else:
            self.icon_image.set_from_pixbuf(get_fallback_icon(24))
        self.icon_label.set_text(label)
    def _on_browse(self, w):
        dlg = AppBrowser(self)
        if dlg.run() == Gtk.ResponseType.OK and dlg.selected_app:
            name, cmd, icon = dlg.selected_app
            self.entry_label.set_text(name)
            self.entry_cmd.set_text(cmd)
            self.icon_name = icon
            self._update_icon_preview()
        dlg.destroy()
    def get_action(self):
        ft_map = {0: ["directory"], 1: ["file"], 2: ["directory", "file"]}
        a = {"label": self.entry_label.get_text().strip(), "type": self.combo_type.get_active_text(),
             "command_line": self.entry_cmd.get_text().strip(),
             "filetypes": ft_map.get(self.combo_ft.get_active(), ["directory"])}
        cwd = self.entry_cwd.get_text().strip()
        if cwd: a["cwd"] = cwd
        if self.check_shell.get_active(): a["use_shell"] = True
        if self.icon_name: a["icon"] = self.icon_name
        return a

class CrudWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title=_("gestor_title"))
        self.set_default_size(750, 500)
        self.connect("destroy", Gtk.main_quit)
        self.config = load_config()
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        vbox.set_margin_start(8); vbox.set_margin_end(8)
        vbox.set_margin_top(8); vbox.set_margin_bottom(8)
        self.add(vbox)
        toolbar = Gtk.Box(spacing=6)
        btn_add = icon_button("list-add", _("btn_add"))
        btn_add.get_style_context().add_class("suggested-action")
        btn_edit = icon_button("gtk-edit", _("btn_edit"))
        btn_delete = icon_button("edit-delete", _("btn_delete"))
        toolbar.pack_start(btn_add, False, False, 0)
        toolbar.pack_start(btn_edit, False, False, 0)
        toolbar.pack_start(btn_delete, False, False, 0)
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        toolbar.pack_start(sep, False, False, 8)
        btn_up = icon_button("go-up", _("btn_up"))
        btn_down = icon_button("go-down", _("btn_down"))
        toolbar.pack_start(btn_up, False, False, 0); toolbar.pack_start(btn_down, False, False, 0)
        vbox.pack_start(toolbar, False, False, 0)
        self.store = Gtk.ListStore(str, str, str)
        self.refresh_store()
        self.treeview = Gtk.TreeView(model=self.store)
        self.treeview.set_headers_visible(True)
        self.treeview.get_selection().set_mode(Gtk.SelectionMode.SINGLE)
        rend = Gtk.CellRendererText()
        col = Gtk.TreeViewColumn(_("col_label"), rend, text=0)
        col.set_resizable(True); col.set_min_width(200); col.set_sort_column_id(0)
        self.treeview.append_column(col)
        rend2 = Gtk.CellRendererText()
        col2 = Gtk.TreeViewColumn(_("col_type"), rend2, text=1)
        col2.set_resizable(True); col2.set_min_width(80)
        self.treeview.append_column(col2)
        rend3 = Gtk.CellRendererText()
        col3 = Gtk.TreeViewColumn(_("col_command"), rend3, text=2)
        col3.set_resizable(True); col3.set_expand(True)
        self.treeview.append_column(col3)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.add(self.treeview); vbox.pack_start(scrolled, True, True, 0)
        hbox_bottom = Gtk.Box(spacing=6)
        self.status = Gtk.Label(label=""); self.status.set_xalign(0)
        hbox_bottom.pack_start(self.status, True, True, 0)
        btn_close = icon_button("window-close", _("btn_close"))
        hbox_bottom.pack_end(btn_close, False, False, 0)
        vbox.pack_start(hbox_bottom, False, False, 0)
        btn_add.connect("clicked", self.on_add)
        btn_edit.connect("clicked", self.on_edit)
        btn_delete.connect("clicked", self.on_delete)
        btn_up.connect("clicked", self.on_up); btn_down.connect("clicked", self.on_down)
        btn_close.connect("clicked", lambda w: self.destroy())
        self.treeview.connect("row-activated", self.on_row_activated)
        self.show_all()
    def refresh_store(self):
        self.store.clear()
        for a in self.config.get("actions", []):
            lbl = a.get("label", ""); typ = a.get("type", "command"); cmd = a.get("command_line", "")
            self.store.append([lbl + (_("suffix_menu") if typ == "menu" else ""), typ, cmd])
    def selected(self):
        s = self.treeview.get_selection(); m, it = s.get_selected()
        return None if it is None else m.get_path(it)[0]
    def on_add(self, w):
        d = FormDialog(self)
        if d.run() == Gtk.ResponseType.OK:
            a = d.get_action()
            if not a["label"]: self.status.set_text(_("status_empty_label")); d.destroy(); return
            self.config["actions"].append(a); save_config(self.config); self.refresh_store()
            self.status.set_text("'" + a["label"] + "' " + _("status_added"))
        d.destroy()
    def on_edit(self, w):
        i = self.selected()
        if i is None: self.status.set_text(_("status_sel_first")); return
        a = self.config["actions"][i]
        d = FormDialog(self, a)
        if d.run() == Gtk.ResponseType.OK:
            new_a = d.get_action()
            if not new_a["label"]: self.status.set_text(_("status_empty_label")); d.destroy(); return
            self.config["actions"][i] = new_a; save_config(self.config); self.refresh_store()
            self.status.set_text("'" + new_a["label"] + "' " + _("status_updated"))
        d.destroy()
    def on_delete(self, w):
        i = self.selected()
        if i is None: self.status.set_text(_("status_sel_first")); return
        a = self.config["actions"][i]
        d = Gtk.MessageDialog(self, 0, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO,
                              _("confirm_delete") + " '" + a["label"] + "'?")
        d.set_title(_("confirm_title"))
        if d.run() == Gtk.ResponseType.YES:
            del self.config["actions"][i]; save_config(self.config); self.refresh_store()
            self.status.set_text("'" + a["label"] + "' " + _("status_deleted"))
        d.destroy()
    def on_up(self, w):
        i = self.selected()
        if i is None or i == 0: return
        self.config["actions"][i], self.config["actions"][i-1] = self.config["actions"][i-1], self.config["actions"][i]
        save_config(self.config); self.refresh_store()
        self.treeview.get_selection().select_path(Gtk.TreePath(i-1))
    def on_down(self, w):
        i = self.selected()
        if i is None or i >= len(self.config["actions"])-1: return
        self.config["actions"][i], self.config["actions"][i+1] = self.config["actions"][i+1], self.config["actions"][i]
        save_config(self.config); self.refresh_store()
        self.treeview.get_selection().select_path(Gtk.TreePath(i+1))
    def on_row_activated(self, tv, path, col):
        self.on_edit(None)

if __name__ == "__main__":
    CrudWindow(); Gtk.main()
PYEOF
    chmod +x "$cfg_dir/gestor.py"

    # ── gestor.sh: wrapper con DISPLAY ──────────────────────
    cat > "$cfg_dir/gestor.sh" << SHEOF
#!/bin/bash
export DISPLAY="\${DISPLAY:-:0}"
/usr/bin/python3 "\$HOME/.local/share/actions-for-nautilus/gestor.py"
SHEOF
    chmod +x "$cfg_dir/gestor.sh"

    # ── enviar-plank.sh: añadir apps al dock ─────────────────
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/enviar-plank.sh" << 'PLankeof'
#!/bin/bash
for f in "$@"; do
    [ -f "$f" ] || continue
    ext="${f##*.}"
    base="$(basename "$f" ."$ext")"
    dir="$(dirname "$f")"
    if [ "$ext" != "desktop" ] && [ "$ext" != "sh" ] && [ ! -x "$f" ]; then
        continue
    fi
    case "$ext" in
        desktop)
            desk="$HOME/.local/share/applications/$(basename "$f")"
            cp -f "$f" "$desk"
            cmd=$(grep '^Exec=' "$desk" | head -1 | cut -d= -f2- | awk '{print $1}')
            if [ -n "$cmd" ] && ! command -v "$cmd" &>/dev/null; then
                full=""
                for p in "$dir/$cmd" "$dir"/*/"$cmd"; do
                    [ -x "$p" ] && full="$p" && break
                done
                [ -n "$full" ] && sed -i "s|^Exec=.*|Exec=$full %f|" "$desk"
            fi
            icon=$(grep '^Icon=' "$desk" | head -1 | cut -d= -f2-)
            if [ -n "$icon" ] && [[ "$icon" != /* ]]; then
                for ext in svg png xpm; do
                    [ -f "$dir/$icon.$ext" ] && sed -i "s|^Icon=.*|Icon=$dir/$icon.$ext|" "$desk" && break
                    [ -f "$dir/$icon" ] && sed -i "s|^Icon=.*|Icon=$dir/$icon|" "$desk" && break
                done
            fi
            ;;
        sh)
            desk="$HOME/.local/share/applications/${base}.desktop"
            cat > "$desk" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$base
Exec=bash "$f"
Terminal=false
Icon=application-x-shellscript
Categories=Utility;
EOF
            chmod +x "$desk"
            ;;
        *)
            desk="$HOME/.local/share/applications/${base}.desktop"
            cat > "$desk" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$base
Exec="$f"
Terminal=false
Icon=application-x-executable
Categories=Utility;
EOF
            chmod +x "$desk"
            for ext in svg png xpm; do
                [ -f "$dir/$base.$ext" ] && sed -i "s|^Icon=.*|Icon=$dir/$base.$ext|" "$desk" && break
            done
            ;;
    esac
    dock="$HOME/.config/plank/dock1/launchers/${base}.dockitem"
    cat > "$dock" << EOF
[PlankDockItemPreferences]
Launcher=file://$desk
EOF
    echo "Añadido: $base → Plank"
done
PLankeof
    chmod +x "$HOME/.local/bin/enviar-plank.sh"

    # ── enviar-escritorio.sh: mandar archivos al escritorio ─
    # Crea accesos directos (symlinks) en el escritorio real, sin asumir
    # que se llama "Escritorio" ni que $HOME sea el mismo en otro PC.
    cat > "$HOME/.local/bin/enviar-escritorio.sh" << 'ESCESEOF'
#!/bin/bash
# Enviar a Escritorio: coloca un acceso directo por cada archivo/carpeta.
DESK="$(xdg-user-dir DESKTOP 2>/dev/null)"
[ -n "$DESK" ] || DESK="$HOME/Escritorio"
[ -d "$DESK" ] || DESK="$HOME/Desktop"
[ -d "$DESK" ] || DESK="$HOME"
mkdir -p "$DESK" 2>/dev/null || true

for f in "$@"; do
    [ -z "$f" ] && continue
    [ -e "$f" ] || [ -L "$f" ] || continue
    ln -sfn "$f" "$DESK/" 2>/dev/null
done
ESCESEOF
    chmod +x "$HOME/.local/bin/enviar-escritorio.sh"

    # ── añadir-plank.py: diálogo GTK para añadir apps ───────
    cat > "$HOME/.local/bin/añadir-plank.py" << 'PLANKPY'
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

# El lanzador del propio "Respaldo" y el de "Anadir a Plank" NO se ofrecen:
# los dos ya estan anclados en el dock, asi que no aportan nada. El de
# Respaldo salia ademas el primero de la lista y sin icono util.
NO_OFRECER = {"plank-backup.desktop", "anadir-a-plank.desktop"}

def anadir_al_dock(nombre_item):
    """Mete el .dockitem en la lista de Plank (dconf).

    Plank BORRA los .dockitem que no estan en esa lista: sin esto, el icono se
    anade y desaparece acto seguido (es decir: no se anade nunca).
    """
    clave = "/net/launchpad/plank/docks/dock1/dock-items"
    try:
        cur = subprocess.run(["dconf", "read", clave],
                             capture_output=True, text=True).stdout.strip()
    except Exception:
        return
    if cur.startswith("@as "): cur = cur[4:]
    if not cur or cur == "[]": cur = "[]"
    if nombre_item in cur: return
    nueva = f"['{nombre_item}']" if cur == "[]" else cur[:-1] + f", '{nombre_item}']"
    subprocess.run(["dconf", "write", clave, nueva], check=False)

def scan_apps():
    apps, seen = [], set()
    fb = get_fallback()
    for d in [APPS_DIR, LOCAL_APPS]:
        if not os.path.isdir(d): continue
        for fname in sorted(os.listdir(d)):
            if not fname.endswith(".desktop") or fname in seen: continue
            if fname in NO_OFRECER: continue
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
            # Una sola linea: si el nombre ocupaba dos, los botones salian de
            # alturas distintas y los iconos quedaban descuadrados.
            lbl.set_lines(1)
            lbl.set_xalign(0.5)
            inner.pack_start(lbl, False, False, 0)
            btn.add(inner)
            btn.set_relief(Gtk.ReliefStyle.NONE)
            # Celda de tamano fijo: todos los iconos igual de grandes.
            btn.set_size_request(84, 84)
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
        anadir_al_dock(f"{slug}.dockitem")
        self.destroy()
        Gtk.main_quit()

if __name__ == "__main__":
    AddWindow(scan_apps())
    Gtk.main()
PLANKPY
    chmod +x "$HOME/.local/bin/añadir-plank.py"

    # ── Copia de seguridad de Plank: añadir botón directo al diálogo "Añadir a Plank" ──
    local dir_proyecto_backup; dir_proyecto_backup=$(cd "$(dirname "$0")" && pwd)
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

        python3 - << 'PYBACKUP2'
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
        'BACKUP_ICON = os.path.expanduser("~/.icons/custom/plank-backup.png")\n'
        'BACKUP_ICON_SVG = os.path.expanduser("~/.icons/custom/plank-backup.svg")',
        1)
    s = s.replace(
        "        self._flow_items = []\n        for name, cmd, icon, pix in self.apps:",
        "        self._flow_items = []\n        self._add_backup_button(q)\n        for name, cmd, icon, pix in self.apps:",
        1)
    s = s.replace(
        "    def _on_flow_btn(self, btn):",
        "    def _add_backup_button(self, q=\"\"):\n"
        "        if q and \"respaldo\" not in q:\n            return\n"
        "        pix = None\n"
        "        for _ic in (BACKUP_ICON, BACKUP_ICON_SVG):\n"
        "            try:\n                pix = GdkPixbuf.Pixbuf.new_from_file_at_size(_ic, 48, 48)\n"
        "                break\n            except Exception:\n                pass\n"
        "        if pix is None:\n            pix = get_fallback()\n"
        "        btn = Gtk.Button()\n"
        "        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)\n"
        "        inner.set_margin_start(4); inner.set_margin_end(4)\n"
        "        inner.set_margin_top(4); inner.set_margin_bottom(4)\n"
        "        inner.pack_start(Gtk.Image.new_from_pixbuf(pix), False, False, 0)\n"
        "        lbl = Gtk.Label(label=\"Respaldo\")\n"
        "        lbl.set_max_width_chars(12)\n        lbl.set_lines(1)\n        lbl.set_xalign(0.5)\n"
        "        inner.pack_start(lbl, False, False, 0)\n"
        "        btn.add(inner)\n"
        "        btn.set_relief(Gtk.ReliefStyle.NONE)\n"
        "        btn.set_size_request(84, 84)\n"
        "        btn.connect(\"clicked\", self._on_backup_clicked)\n"
        "        self.flow.add(btn)\n\n"
        "    def _on_backup_clicked(self, w):\n"
        "        if os.path.exists(BACKUP_SCRIPT):\n"
        "            subprocess.Popen([\"bash\", BACKUP_SCRIPT])\n"
        "        self.destroy()\n\n"
        "    def _on_flow_btn(self, btn):",
        1)
    open(p, "w").write(s)
PYBACKUP2
        info "Botón de respaldo de Plank añadido al diálogo 'Añadir a Plank'"
    fi

    # ── añadir-plank.sh: diálogo zenity ─────────────────────
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

    # ── Menú escritorio: Añadir a Plank ─────────────────────
    xfconf-query -c xfce4-desktop -p /desktop-menu/show -s true 2>/dev/null || true
    mkdir -p "$HOME/.config/menus/applications-merged" "$HOME/.local/share/desktop-directories"
    cat > "$HOME/.config/menus/applications-merged/plank-custom.menu" << 'MENUEOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>Plank</Name>
    <Directory>plank.directory</Directory>
    <Include>
      <Filename>anadir-a-plank.desktop</Filename>
    </Include>
  </Menu>
</Menu>
MENUEOF
    cat > "$HOME/.local/share/desktop-directories/plank.directory" << 'DIREOF'
[Desktop Entry]
Name=Plank
Icon=list-add
Type=Directory
DIREOF
    # OJO: heredoc SIN comillas, a proposito, para que $HOME se expanda.
    # Con << 'DESKEOF' el $HOME sale LITERAL en el .desktop, y entonces:
    #   • el Icon no existe -> el icono sale vacio,
    #   • el Exec no arranca -> hay que abrir la app a mano,
    #   • el Launcher=file://$HOME/... no lo resuelve Plank -> borra el
    #     .dockitem y el acceso desaparece del dock.
    cat > "$HOME/.local/share/applications/anadir-a-plank.desktop" << DESKEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Añadir a Plank
Comment=Busca y añade cualquier aplicación al dock de Plank
Exec=python3 $HOME/.local/bin/añadir-plank.py
Terminal=false
Icon=$HOME/.icons/custom/dock-add.svg
Categories=Utility;
NoDisplay=false
DESKEOF
    chmod +x "$HOME/.local/share/applications/anadir-a-plank.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1

    local dir_dock="$HOME/.config/plank/dock1/launchers"
    mkdir -p "$dir_dock"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' \
        "$HOME/.local/share/applications/anadir-a-plank.desktop" \
        > "$dir_dock/aaa_anadir-a-plank.dockitem"

    # ── En el dock, justo a la DERECHA de "Respaldo" ─────────────────────────
    # Plank usa el ORDEN de esta lista de dconf, asi que hay que insertarlo en
    # su sitio: al final se queda desligado de "Respaldo" y el primero taparia
    # el acceso a las demas apps. "Respaldo" lleva el prefijo aaa_0_ justamente
    # para poder ser el primero del dock.
    local _clave=/net/launchpad/plank/docks/dock1/dock-items
    local cur
    cur=$(dconf read "$_clave" 2>/dev/null | sed 's/^@as //')
    [ -n "$cur" ] || cur="[]"
    if ! printf '%s' "$cur" | grep -q "aaa_anadir-a-plank.dockitem"; then
        if [ "$cur" = "[]" ]; then
            cur="['aaa_anadir-a-plank.dockitem']"
        elif printf '%s' "$cur" | grep -q "aaa_0-respaldo.dockitem"; then
            cur=$(printf '%s' "$cur" | sed \
                "s/aaa_0-respaldo\.dockitem'/aaa_0-respaldo.dockitem', 'aaa_anadir-a-plank.dockitem'/")
        else
            cur=$(printf '%s' "$cur" | sed "s/]$/, 'aaa_anadir-a-plank.dockitem']/")
        fi
        case "$cur" in
            "['"*"']") dconf write "$_clave" "$cur" 2>/dev/null || true ;;
        esac
    fi

    # ── config.json: gestor + útiles ────────────────────────
    cat > "$cfg_dir/config.json" << JSONEOF
{
  "actions": [
    {
      "type": "command",
      "label": "Abrir Consola",
      "command_line": "konsole --workdir %f",
      "max_items": 1,
      "filetypes": ["directory"],
      "icon": "terminal"
    },
    {
      "type": "command",
      "label": "Copiar ruta",
      "command_line": "echo -n %F | xclip -selection clipboard",
      "use_shell": true,
      "use_v1_interpolation": false,
      "icon": "edit-copy"
    },

    {
      "type": "command",
      "label": "Gestor de Acciones",
      "command_line": "/usr/bin/bash $HOME/.local/share/actions-for-nautilus/gestor.sh",
      "filetypes": ["directory"],
      "icon": "preferences-system"
    },
    {
      "type": "command",
      "label": "Abrir con Visual Studio Code",
      "command_line": "code %F",
      "use_shell": true,
      "use_v1_interpolation": false,
      "filetypes": ["file", "directory"],
      "icon": "code"
    },
    {
      "type": "command",
      "label": "Enviar a Escritorio",
      "command_line": "bash \$HOME/.local/bin/enviar-escritorio.sh %F",
      "use_shell": true,
      "use_v1_interpolation": false,
      "filetypes": ["file", "directory"],
      "icon": "user-desktop"
    },
    {
      "type": "command",
      "label": "Enviar a Plank",
      "command_line": "bash $HOME/.local/bin/enviar-plank.sh %F",
      "use_shell": true,
      "filetypes": ["file"],
      "mimetypes": ["application/x-desktop", "application/x-shellscript", "application/x-executable", "application/x-sharedlib"],
      "icon": "application-x-shellscript",
      "description": "Añade un ejecutable o app al dock de Plank"
    }
  ],
  "sort": "manual",
  "debug": false
}
JSONEOF

    # ── Parchear extensión Actions for Nautilus para soportar iconos ──
    if [ -f "$EXT/afn_config.py" ] && [ -f "$EXT/afn_menu.py" ]; then
        step "Parcheando extensión para iconos en menú contextual"
        cat > /tmp/patch_icons.py << 'PYEOF'
import re, sys
ext = sys.argv[1]
cf = ext + "/afn_config.py"
mf = ext + "/afn_menu.py"
with open(cf) as f:
    c = f.read()
if 'self.icon = ""' not in c:
    c = c.replace(
        "self.use_shell = False\n        self.min_items = 1",
        "self.use_shell = False\n        self.icon = \"\"\n        self.min_items = 1",
    )
if 'action.icon = json_action.get("icon", "")' not in c:
    c = c.replace(
        "action.use_shell = json_action[\"use_shell\"]",
        "action.use_shell = json_action[\"use_shell\"]\n        action.icon = json_action.get(\"icon\", \"\")",
    )
c = re.sub(r'(action\.icon = json_action\.get\("icon", ""\)\s*){2,}', r'\1', c)
with open(cf, "w") as f:
    f.write(c)
with open(mf) as f:
    m = f.read()
if ", icon=action.icon" not in m:
    m = m.replace(
        "menu_item = Nautilus.MenuItem(name=name, label=label)",
        "menu_item = Nautilus.MenuItem(name=name, label=label, icon=action.icon)",
    )
with open(mf, "w") as f:
    f.write(m)
print("Extension patched OK")
PYEOF
        sudo python3 /tmp/patch_icons.py "$EXT"
        rm -f /tmp/patch_icons.py
    fi

    # ── Acceso directo en menu de aplicaciones ──────────────
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/gestor-acciones-nautilus.desktop << DESKEOF
[Desktop Entry]
Type=Application
Name=Gestor de Acciones Nautilus
Comment=Anadir y editar acciones del menu contextual de Nautilus
Exec=$cfg_dir/gestor.sh
Icon=preferences-system
Terminal=false
Categories=Utility;
NoDisplay=true
DESKEOF
    chmod +x ~/.local/share/applications/gestor-acciones-nautilus.desktop 2>/dev/null || true

    info "Gestor instalado — aparece en espacio vacio de las carpetas"
}


nautilus_transparencia() {
    # Ventana de Files (Nautilus) translúcida estilo macOS.
    # Se hace con CSS de usuario: el fondo de la ventana pasa a rgba y el
    # contenido queda transparente. picom respeta ese alfa (detect-client-opacity)
    # siempre que Nautilus no esté en la lista de "forzar opaco" de picom.sh.
    step "Nautilus: ventana translúcida"

    local alfa_ventana alfa_cabecera color
    if [ "$MODO" = "light" ]; then
        color="246,246,246"
        alfa_ventana="0.88"
        alfa_cabecera="0.78"
    else
        color="38,38,38"
        alfa_ventana="0.86"
        alfa_cabecera="0.72"
    fi

    local dir3="$HOME/.config/gtk-3.0" dir4="$HOME/.config/gtk-4.0"
    mkdir -p "$dir3" "$dir4"

    local css
    # OJO: sin espacios dentro de rgba() y sin !important — el parser CSS de
    # GTK3 rechaza ambas cosas ("Junk at end of value") y descarta la regla.
    # No hace falta !important: el CSS del usuario se carga DESPUÉS del tema
    # y por tanto gana en los empates de especificidad.
    css="/* macOS XFCE - Files (Nautilus) translúcido
 * El fondo de la ventana usa alfa para que se vea el wallpaper a través.
 * Contenido transparente; cabecera y barra lateral semitransparentes.
 */

window.nautilus-window,
window.nautilus-window.background {
    background-color: rgba(${color},${alfa_ventana});
    background-image: none;
}

window.nautilus-window .nautilus-window-content,
window.nautilus-window treeview.view,
window.nautilus-window .view,
window.nautilus-window .nautilus-canvas-item {
    background-color: transparent;
    background-image: none;
}

window.nautilus-window headerbar,
window.nautilus-window .header-bar,
window.nautilus-window toolbar,
window.nautilus-window menubar,
window.nautilus-window .floating-header,
window.nautilus-window .sidebar,
window.nautilus-window .navigation-sidebar {
    background-color: rgba(${color},${alfa_cabecera});
    background-image: none;
}
"

    # GTK3 lee ~/.config/gtk-3.0/gtk.css (se añade al tema del sistema)
    printf '%s' "$css" > "$dir3/macos-nautilus.css"
    local import3='@import url("file://'"$dir3"'/macos-nautilus.css");'
    touch "$dir3/gtk.css"
    grep -qF 'macos-nautilus.css' "$dir3/gtk.css" || echo "$import3" >> "$dir3/gtk.css"

    # GTK4 (Nautilus 45+): este archivo lo reescribe aplicar_modo_oscuro, que ya
    # se encarga de importar también este override.
    printf '%s' "$css" > "$dir4/macos-nautilus.css"

    info "Nautilus translúcido (alfa ${alfa_ventana}) — reinicia Nautilus para aplicarlo"
}


nautilus_relanzar() {
    step "Reiniciando Nautilus"

    # Thunar --daemon roba org.freedesktop.FileManager1 en D-Bus.
    # Si Firefox llama ShowItems, la petición va a Thunar y no abre Nautilus.
    systemctl --user stop thunar.service 2>/dev/null || true
    thunar -q 2>/dev/null || true
    pkill -9 Thunar 2>/dev/null || true
    sleep 1

    pkill -9 nautilus 2>/dev/null || true
    sleep 2

    # Relanzar Nautilus con tema macOS y CSD para que las decoraciones se vean al instante
    mkdir -p ~/.config/autostart
    DISPLAY="${DISPLAY:-:0}" nohup env GTK_THEME="$TEMA" GTK_CSD=1 nautilus --gapplication-service > /dev/null 2>&1 &
    sleep 2
    info "Nautilus relanzado con tema $TEMA y CSD forzado"
}

nautilus_desinstalar_thunar() {
    step "Neutralizando Thunar (se conserva solo para ZIP en escritorio)"
    apt_silencioso install thunar-archive-plugin

    # ── Impedir que el binario thunar se ejecute ──────────────────
    # dpkg-divert renombra /usr/bin/thunar a /usr/bin/thunar.distrib
    # y pone nuestro dummy en su lugar. Así 'thunar --daemon' no hace nada,
    # pero thunar-archive-plugin sigue cargando sus librerías para el menú
    # contextual del escritorio.
    if [ -f /usr/bin/thunar ] && [ ! -f /usr/bin/thunar.distrib ]; then
        sudo dpkg-divert --add --rename --divert /usr/bin/thunar.distrib /usr/bin/thunar >/dev/null 2>&1
    fi
    # Wrapper: llama a thunar real excepto --daemon
    # Necesario para que "Propiedades" y "Renombrar" del escritorio funcionen
    sudo tee /usr/bin/thunar > /dev/null << 'THUNARFAKE'
#!/bin/bash
for arg in "$@"; do
    [ "$arg" = "--daemon" ] && exit 0
done
exec /usr/bin/thunar.distrib "$@"
THUNARFAKE
    sudo chmod 755 /usr/bin/thunar

    # ── Eliminar servicio FileManager1 de Thunar ──────────────────
    sudo rm -f /usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service
    sudo rm -f /usr/share/dbus-1/services/org.xfce.Thunar.FileManager1.service.disabled
    rm -f ~/.local/share/dbus-1/services/org.xfce.Thunar.FileManager1.service

    # ── Crear D-Bus services para org.xfce.Thunar y org.xfce.FileManager
    #     sin systemd (evita el masking). Necesarios para "Renombrar" en escritorio.
    mkdir -p ~/.local/share/dbus-1/services
    cat > ~/.local/share/dbus-1/services/org.xfce.Thunar.service << 'THUNARDBUS'
[D-BUS Service]
Name=org.xfce.Thunar
Exec=/usr/bin/thunar --gapplication-service
THUNARDBUS
    cat > ~/.local/share/dbus-1/services/org.xfce.FileManager.service << 'XFMPDBUS'
[D-BUS Service]
Name=org.xfce.FileManager
Exec=/usr/bin/thunar --gapplication-service
XFMPDBUS

    # ── Desenmascarar thunar.service si estaba masked ────────────
    systemctl --user unmask thunar.service 2>/dev/null || true

    # ── Evitar que xfce4-session resucite Thunar al reiniciar ────
    rm -rf ~/.cache/sessions/xfce4-*
    rm -f ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml

    # ── Ocultar Thunar de menús ───────────────────────────────────
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/thunar.desktop << 'HIDETHUNAR'
[Desktop Entry]
Type=Application
Name=Thunar
Exec=thunar %U
Icon=thunar
Hidden=true
NoDisplay=true
HIDETHUNAR
    update-desktop-database ~/.local/share/applications 2>/dev/null || true

    # Eliminar cualquier .desktop de Thunar del sistema
    sudo rm -f /usr/share/applications/thunar.desktop
    sudo rm -f /usr/local/share/applications/thunar.desktop
    sudo rm -f /usr/share/applications/Thunar-folder-handler.desktop

    # ── Autostart: evitar que Thunar se lance con la sesión ──────
    mkdir -p ~/.config/autostart
    if [ -f /etc/xdg/autostart/thunar-daemon.desktop ]; then
        sudo rm -f /etc/xdg/autostart/thunar-daemon.desktop
    fi
    # Crear un autostart que no haga nada (mata cualquier resurrección)
    cat > ~/.config/autostart/thunar-desktop-archive.desktop << 'AUTOTHUNAR'
[Desktop Entry]
Type=Application
Name=Thunar Desktop Archive
Exec=bash -c "pkill -9 thunar 2>/dev/null; pkill -9 Thunar 2>/dev/null; exit 0"
Hidden=true
X-GNOME-Autostart-enabled=false
AUTOTHUNAR
    chmod +x ~/.config/autostart/thunar-desktop-archive.desktop 2>/dev/null || true

    # ── Matar cualquier proceso thunar vivo ──────────────────────
    systemctl --user stop thunar.service 2>/dev/null || true
    thunar -q 2>/dev/null || true
    pkill -9 thunar 2>/dev/null || true
    pkill -9 Thunar 2>/dev/null || true
    sleep 1

    update-desktop-database ~/.local/share/applications 2>/dev/null || true

    info "Thunar neutralizado. ZIP en escritorio activo, Firefox usa Nautilus."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA ICONOS

    paso="${2:-todo}"
    case "$paso" in
        configurar)   nautilus_configurar ;;
        relanzar)     nautilus_relanzar ;;
        extension)    nautilus_extension_menu ;;
        ocultar)      nautilus_desinstalar_thunar ;;
        transparencia) nautilus_transparencia ;;
        todo)
            nautilus_configurar
            nautilus_extension_menu
            nautilus_transparencia
            nautilus_relanzar
            ;;
    esac
fi
