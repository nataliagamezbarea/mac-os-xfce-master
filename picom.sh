#!/bin/bash
# picom.sh — compositor único (picom). TODO OPACO, salvo las apps que TÚ elijas.
#
# Elige qué apps llevan transparencia en la lista de abajo (clase WM_CLASS).
# Para saber la clase de una app:  xprop WM_CLASS   y clic en su ventana.
# También puedes añadirlas sin tocar el script, una por línea, en:
#   ~/.config/picom/transparentes.txt
# Todo lo que NO esté en la lista se fuerza a opaco (Unity, Unity Hub,
# panel superior, etc.). Después de editar la lista: bash picom.sh
#
# Ventanas GTK con decoración propia (_GTK_FRAME_EXTENTS) y menús/notificaciones
# se dejan tal cual: necesitan su alfa para sombras y esquinas redondeadas.

APPS_TRANSPARENTES=(
    "Xfce4-panel"      # panel superior (se ve el fondo de pantalla)
    "Plank"            # dock
    "Ulauncher"        # lanzador (tiene marco/sombra propios)
    "Konsole"          # terminal con Opacity/Blur de terminal.sh
    "Xfce4-terminal"
    "Nautilus"         # Files: ventana translúcida (CSS de nautilus.sh)
)

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

PICOM_DIR="$HOME/.config/picom"
PICOM_CONF="$PICOM_DIR/picom.conf"
PICOM_SHADER="$PICOM_DIR/opaque.glsl"
PICOM_LISTA="$PICOM_DIR/transparentes.txt"

# Construye la condición de picom a partir de la lista (script + archivo)
picom_condicion() {
    local clases=("${APPS_TRANSPARENTES[@]}") linea
    if [ -f "$PICOM_LISTA" ]; then
        while IFS= read -r linea; do
            linea="${linea%%#*}"; linea="$(echo "$linea" | xargs)"
            [ -n "$linea" ] && clases+=("$linea")
        done < "$PICOM_LISTA"
    fi
    local cond="" c
    for c in "${clases[@]}"; do
        c="${c%%#*}"; c="$(echo "$c" | xargs)"
        [ -z "$c" ] && continue
        cond+="${cond:+ || }class_g = '$c'"
    done
    # Tipos que no se tocan (menús, notificaciones...) y GTK con marco propio
    local tipos="window_type = 'dnd' || window_type = 'notification' || window_type = 'tooltip' || window_type = 'popup_menu' || window_type = 'dropdown_menu' || window_type = 'menu' || window_type = 'combo'"
    if [ -n "$cond" ]; then
        echo "!($cond) && !($tipos) && !_GTK_FRAME_EXTENTS@:c"
    else
        echo "!($tipos) && !_GTK_FRAME_EXTENTS@:c"
    fi
}

picom_instalar() {
    command -v picom &>/dev/null && return 0
    step "Instalando picom"
    apt_silencioso install picom 2>/dev/null || true
    command -v picom &>/dev/null
}

picom_escribir_config() {
    mkdir -p "$PICOM_DIR"

    # Shader: fuerza alfa = 1.0 (ventana completamente opaca)
    cat > "$PICOM_SHADER" << 'GLSLEOF'
#version 330
in vec2 texcoord;
uniform sampler2D tex;
vec4 window_shader() {
    vec4 c = texelFetch(tex, ivec2(texcoord), 0);
    c.a = 1.0;
    return c;
}
GLSLEOF

    cat > "$PICOM_CONF" << CONFEOF
#################################
#           Corners             #
#################################
corner-radius = 10.0;
rounded-corners-exclude = [
  "class_g = 'awesome'",
  "class_g = 'URxvt'",
  "class_g = 'XTerm'",
  "class_g = 'kitty'",
  "class_g = 'Alacritty'",
  "class_g = 'Polybar'",
  "class_g = 'code-oss'",
  "class_g = 'firefox'",
  "class_g = 'Conky'",
  "class_g = 'Thunderbird'",
  "class_g ?= 'xfce4-panel' && window_type = 'dock'"
];
round-borders = 1;
round-borders-exclude = [];
round-borders-rule = [
  "3:class_g      = 'XTerm'",
  "3:class_g      = 'URxvt'",
  "10:class_g     = 'Alacritty'",
  "15:class_g     = 'Signal'"
];

#################################
#             Shadows           #
#################################
shadow = false;
shadow-radius = 7;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-exclude = [
  "name = 'Notification'",
  "class_g = 'Conky'",
  "class_g ?= 'Notify-osd'",
  "class_g = 'Cairo-clock'",
  "class_g = 'slop'",
  "class_g = 'Polybar'",
  "class_g = 'Ulauncher'",
  "_GTK_FRAME_EXTENTS@:c"
];

#################################
#           Fading              #
#################################
# SIN FADING: con fading=true y fade-in-step=0.03 cada ventana y cada menú
# (clic derecho) tardaba ~0,5 s en aparecer — se veía como una animación lenta.
# Los menús usan el tipo "menu", que no estaba en wintypes y heredaba el fade.
fading = false;
fade-in-step = 0.06;
fade-out-step = 0.06;
fade-exclude = [
  "class_g = 'slop'"
];

#################################
#   Transparency / Opacity      #
#################################
# TODO OPACO por defecto: nada se vuelve transparente al perder el foco.
inactive-opacity = 1.0;
frame-opacity = 1.0;
active-opacity = 1.0;
inactive-opacity-override = false;
focus-exclude = [
  "class_g = 'Cairo-clock'",
  "class_g = 'Bar'",
  "class_g = 'slop'"
];
# Solo lo que DEBE ser translúcido (ninguna app normal aquí).
opacity-rule = [
  "80:class_g     = 'Bar'",
  "80:class_g     = 'Polybar'"
];

# Alfa=1 en TODO salvo las apps de la lista APPS_TRANSPARENTES (ver picom.sh)
window-shader-fg-rule = [
  "$PICOM_SHADER:$(picom_condicion)"
];

#################################
#     Background-Blurring       #
#################################
blur-kern = "3x3box";
blur: {
  method = "dual_kawase";
  strength = 4;
  background = false;
  background-frame = false;
  background-fixed = false;
  kern = "3x3box";
}
blur-background-exclude = [
  "class_g ?= 'plank' && window_type = 'dock'",
  "class_g = 'Ulauncher'",
  "class_g = 'Conky'&& window_type = 'desktop'",
  "class_g = 'slop'",
  "_GTK_FRAME_EXTENTS@:c"
];

#################################
#       General Settings        #
#################################
backend = "glx";
vsync = true;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
detect-transient = true;
detect-client-leader = true;
use-damage = true;
log-level = "info";

wintypes:
{
  normal = { fade = false; shadow = false; }
  dialog = { fade = false; shadow = false; }
  menu = { fade = false; shadow = false; focus = true; full-shadow = false; };
  utility = { fade = false; shadow = false; focus = true; full-shadow = false; };
  tooltip = { fade = false; shadow = false; focus = true; full-shadow = false; };
  dock = { shadow = false; fade = false; }
  dnd = { shadow = false; fade = false; }
};
CONFEOF
    info "picom.conf y opaque.glsl escritos en $PICOM_DIR"
}

picom_autostart() {
    local dir="$HOME/.config/autostart"
    mkdir -p "$dir"
    cat > "$dir/picom.desktop" << DESKEOF
[Desktop Entry]
Type=Application
Name=Picom
Exec=picom --config $PICOM_CONF -b
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
NoDisplay=true
DESKEOF
    info "Autostart de picom creado"
}

arreglar_unity_vulkan() {
    # Busca instalaciones de Unity Editor y asegura que usen Vulkan
    # para evitar pantalla transparente y fallos de shader de OpenGL en Linux
    for editor in "$HOME"/Unity/Hub/Editor/*/Editor/Unity; do
        [ -f "$editor" ] || continue
        if file "$editor" | grep -q "ELF"; then
            step "Configurando wrapper Vulkan para Unity Editor en $(basename "$(dirname "$(dirname "$editor")")")"
            mv "$editor" "${editor}.bin"
            cat > "$editor" << 'UEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/Unity.bin" -force-vulkan "$@"
UEOF
            chmod +x "$editor"
        fi
    done
}

picom_aplicar() {
    step "Compositor: picom (todo opaco por defecto)"
    if ! picom_instalar; then
        warn "picom no disponible: se deja el compositor de xfwm4 (Unity podría verse transparente)"
        return 0
    fi

    picom_escribir_config
    picom_autostart
    arreglar_unity_vulkan

    # Un solo compositor: apagar el de xfwm4
    xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false 2>/dev/null \
        || xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true

    pkill -x picom 2>/dev/null || true
    sleep 1
    mkdir -p "$HOME/.cache/mac-os-xfce"
    (setsid picom --config "$PICOM_CONF" -b > "$HOME/.cache/mac-os-xfce/picom.log" 2>&1 &)
    sleep 2
    if pgrep -x picom >/dev/null; then
        info "picom corriendo"
    else
        warn "picom no arrancó, revisa ~/.cache/mac-os-xfce/picom.log"
        warn "Reactivando compositor de xfwm4 como respaldo"
        xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
    fi
}

# Compatibilidad con optimizar.sh
optimizar_picocompton() { picom_aplicar; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    picom_aplicar
fi
