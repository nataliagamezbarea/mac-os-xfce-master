#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# plank-backup.sh — RESPALDO de Plank + tus cosas, A TU ELECCIÓN
#
# Al exportar lo primero que pregunta es "¿respaldo TODO?" (lo normal). Si
# dices que no, eliges entre:
#   • Solo los paquetes               → config + lanzadores + scripts + iconos,
#                                       y la lista de TODOS los manuales
#   • Navbar + solo paquetes de navbar → lo anterior, con solo los paquetes
#                                       de las apps ancladas al dock
#   • Todo                             → lo anterior + las dos listas
#
# La copia se hace con una BARRA DE PROGRESO (se puede cancelar) y el resumen
# final trae "Volver atrás" para rehacerla sin empezar de cero.
#
# Guarda / restaura:
#   • Configuración de Plank (dock + lanzadores de la navbar) y temas
#   • LOS .DESKTOP REALES que usa cada lanzador del dock (estuvieran donde
#     estuvieran: ~/.local/share/applications, /usr/share/applications, etc.)
#     y sus recursos (iconos y ejecutables por ruta absoluta), con un mapa
#     "de dónde venía", para que al restaurar en OTRO PC funcione IGUAL,
#     aunque cambies el escritorio o el .desktop original.
#   • Apps personalizadas de ~/.local/share/applications (Safari→Brave, …)
#   • Scripts de ~/.local/bin  • Autostart  • Iconos de ~/.icons/custom
#   • Listas: apps del navbar y paquetes manuales
#   • Repositorios y claves apt (/etc/apt/sources.list.d + keyrings), para que
#     "instalar.sh" funcione en un PC recién formateado (sin repos/keys)
#   • Script "instalar.sh" para reinstalar los paquetes en otro ordenador
# ─────────────────────────────────────────────────────────────────────────────

PLANK_CONFIG="$HOME/.config/plank"
PLANK_THEMES="$HOME/.local/share/plank/themes"
APPS_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
ICONS_CUSTOM="$HOME/.icons/custom"
FECHA=$(date +%Y%m%d-%H%M%S)

# ── NO HAY NINGÚN TOPE DE TAMAÑO ──────────────────────────────────────────────
# Lo único que decide si una app viaja copiada en el respaldo o solo apuntada
# es si se sabe VOLVER A OBTENERLA IGUAL. Si se sabe, se anota su origen con su
# versión exacta y al importar se recupera byte a byte: no se pierde nada y el
# respaldo tarda segundos. Si NO se sabe, se copia la carpeta entera, aunque
# pese 20 MB o 4 GB, porque perder la app no es una opción.
#
# Este valor solo sirve para AVISAR en el resumen ("ojo, esto ocupa 4 GB"),
# nunca para dejar de copiar.
LIMITE_AVISO_MB=500

# A partir de este tamaño, un "ejecutable" que apunta un lanzador del dock deja
# de ser un script y es una APP ENTERA (los de electron pesan 200 MB o más).
# Solo se usa para decidir si hay que preguntarle de dónde sale antes de
# copiarla; si no se sabe, se copia igual. No descarta nada.
LIMITE_EJECUTABLE_MB=120
DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

# El icono de las ventanas. El PNG va PRIMERO a proposito: hay PCs sin
# cargador de SVG, y entonces un .svg sale vacio o borroso.
ICONO="$HOME/.icons/custom/plank-backup.png"
[ -f "$ICONO" ] || ICONO="$HOME/Escritorio/GITHUB/icon.png"
[ -f "$ICONO" ] || ICONO="$HOME/.icons/custom/plank-backup.svg"
[ -f "$ICONO" ] || ICONO="$DIR/icon-plank-backup.svg"

ZEN=(zenity --window-icon="$ICONO")

if ! command -v zenity >/dev/null 2>&1; then
    echo "zenity no está instalado. Ejecuta: sudo apt install zenity"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Índice de paquetes que apt PUEDE instalar, construido UNA sola vez.
#
# Antes se respondía a "¿este paquete viene de algún repositorio?" con un
# `grep -rq "^Package: X$" /var/lib/apt/lists/` POR CADA paquete. Ese
# directorio pesa 274 MB y hay ~1900 paquetes, así que una sola respuesta costaba
# 0,15 s y el respaldo entero se iba en 5-10 minutos de ventana en blanco. Con
# esto se lee el índice una vez (0,6 s) y el resto son búsquedas en un fichero
# de texto plano.
# ─────────────────────────────────────────────────────────────────────────────
APT_IDX_CACHE=""

apt_indice_disponibles() {
    [ -n "$APT_IDX_CACHE" ] && [ -s "$APT_IDX_CACHE" ] && return 0
    APT_IDX_CACHE=$(mktemp) || return 1
    grep -h '^Package: ' /var/lib/apt/lists/*Packages 2>/dev/null \
        | awk '{print $2}' | sort -u > "$APT_IDX_CACHE" 2>/dev/null
    [ -s "$APT_IDX_CACHE" ]
}

# ¿apt puede instalar este paquete por sí solo (o sea, hay repositorio)?
apt_tiene_repo() {
    apt_indice_disponibles || return 1
    grep -qxF "$1" "$APT_IDX_CACHE" 2>/dev/null
}

apt_indice_limpiar() {
    [ -n "$APT_IDX_CACHE" ] && rm -f "$APT_IDX_CACHE" 2>/dev/null
    APT_IDX_CACHE=""
}

plank_reiniciar() {
    pkill -x plank 2>/dev/null || true
    sleep 1
    nohup plank >/tmp/plank.log 2>&1 &
    sleep 2
}

# ─── El propio "Respaldo" en el dock ──────────────────────────────────────────
# Que aparezca anclado (fijado) en el dock, con SU icono y SU nombre, sin
# tener que hacerlo a mano cada vez que se instala esto en un PC.
#
# Importante: solo se toca algo si de verdad hace falta. Si ya esta todo en su
# sitio no se escribe nada y NO se reinicia Plank, que si no el dock
# parpadea cada vez que se abre este menu.
#
# El icono es un PNG (no un .svg): hay PCs donde no hay ningun cargador de
# SVG instalado y entonces el icono no se pinta o sale borroso.
plank_asegurar_lanzador() {
    local desk="$HOME/.local/share/applications/plank-backup.desktop"
    local dir="$PLANK_CONFIG/dock1/launchers"
    local icon="$HOME/.icons/custom/plank-backup.png"
    local tmp cambio=0 f viejo

    # Plank ordena el dock por NOMBRE de fichero. "Anadir a Plank" es el
    # primero (lleva el prefijo aaa_ a proposito), asi que para que "Respaldo"
    # quede justo a su IZQUIERDA el nombre tiene que ordenar antes que el suyo:
    # "aaa_0-respaldo" < "aaa_anadir-a-plank" (el 0 va antes que la a).
    local item="$dir/aaa_0-respaldo.dockitem"

    [ -f "$icon" ] || return 0
    mkdir -p "$HOME/.local/share/applications" "$dir" 2>/dev/null || return 0

    # El dock tiene que.launchar SIEMPRE la copia instalada en ~/.local/bin,
    # no la carpeta de donde se esté ejecutando este script ahora mismo (que
    # puede ser un Descargado de prueba). Es la misma que panel.sh y
    # nautilus.sh mantienen actualizada.
    local ruta="$HOME/.local/bin/plank-backup.sh"
    [ -f "$ruta" ] || ruta="$DIR/plank-backup.sh"

    # ── 1) el .desktop, con el nombre corto ("Respaldo") y el icono bueno ──
    tmp=$(mktemp) || return 0
    cat > "$tmp" <<FIN
[Desktop Entry]
Type=Application
Version=1.0
Name=Respaldo
Name[es]=Respaldo
Comment=Respaldar o restaurar el dock, los lanzadores, los scripts y los paquetes
Comment[es]=Respaldar o restaurar el dock, los lanzadores, los scripts y los paquetes
Exec=bash "$ruta"
Icon=$icon
Terminal=false
Categories=Utility;Settings;System;
StartupNotify=true
FIN
    if ! cmp -s "$tmp" "$desk"; then
        cp -f "$tmp" "$desk" 2>/dev/null
        desktop-update >/dev/null 2>&1
        cambio=1
    fi
    rm -f "$tmp"

    # ── 2) el .dockitem: es lo que hace que quede ANCLADO en el dock ──
    # (todo lanzador con su .dockitem es un icono fijado; sin él, no sale).
    tmp=$(mktemp) || return 0
    {
        echo "[PlankDockItemPreferences]"
        echo "Launcher=file://$desk"
    } > "$tmp"
    if ! cmp -s "$tmp" "$item"; then
        cp -f "$tmp" "$item" 2>/dev/null && cambio=1
    fi
    rm -f "$tmp"

    # ── 2b) fuera los .dockitem viejos de ESTE mismo lanzador ──────────────
    # Si el fichero se llamaba de otra forma (por ejemplo plank-backup), el
    # icono se veria duplicado en el dock: el viejo sigue ahi y no se sabe
    # cual de los dos es el bueno. Se borra cualquiera que apunte al mismo
    # .desktop y no tenga ya el nombre correcto.
    for f in "$dir"/*.dockitem; do
        [ -e "$f" ] || continue
        [ "$f" = "$item" ] && continue
        grep -qF "Launcher=file://$desk" "$f" 2>/dev/null || continue
        rm -f "$f" && cambio=1
    done

    # ── 3) el ORDEN. Plank no lo guarda en los ficheros: lo tiene en dconf
    #    (/net/launchpad/plank/docks/dock1/dock-items), y ademas BORRA los
    #    .dockitem que no esten en esa lista. Por eso hay que tocar esa clave,
    #    pero SOLO para que esten todos: el orden es cosa del usuario y esta
    #    funcion no mueve ni un icono de sitio. Lo unico que hace es:
    #      • quitar de la lista los .dockitem que ya no existen, y
    #      • anadir AL FINAL los que falten (p. ej. este, la primera vez).
    orden_dock_asegurar

    # ── 4) si se ha tocado algo, Plank recarga y ya se ve el icono ──
    [ "$cambio" -eq 1 ] && plank_reiniciar
    return 0
}

# ─── Lanzadores portátiles ─────────────────────────────────────────────────────
# Un .dockitem de Plank solo guarda la RUTA de un .desktop
# (p. ej. Launcher=file:///home/user/.local/share/applications/safari.desktop).
# Si en el otro PC esa ruta no existe (o cambiaste el .desktop), el lanzador
# se rompe. Para evitarlo, al exportar se guardan también los .desktop REALES
# que usa el dock y los recursos que referencian (iconos y ejecutables por
# ruta absoluta), con un mapa de dónde venía cada cosa. Al importar se
# recolocan en este PC y se reescriben los .dockitem para que apunten a algo
# que exista → funciona EXACTAMENTE igual estés donde estés.

archivo_referido() {  # ruta del .desktop que usa un dockitem
    sed -n 's/^Launcher=file:\/\///p' "$1" | head -1 | tr -d '\r'
}

recurso_del_sistema() {  # ¿es de un paquete del sistema? esos no se copian al ZIP
    case "$1" in
        /usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*|/lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*|/usr/share/*|/etc/*)
            return 0 ;;
        *) return 1 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Por qué estas dos funciones existen
#
# Un .dockitem de Plank solo guarda la RUTA de un .desktop. Si al exportar esa
# ruta ya no existe (el paquete se movio, alguien renombro el archivo, se
# borro...), antes el lanzador se descartaba ENTERO del respaldo. Al importar,
# ese .dockitem se quedaba apuntando a un archivo inexistente y el icono
# desaparecia del dock. Y como el respaldo de apps se apoya en los .deb (que a
# veces ya no estan en el disco), el .desktop guardado era la unica red: si
# faltaba, no habia nada.
#
# Ahora el .desktop se copia SIEMPRE, de una de estas tres maneras, por orden:
#   1. La ruta exacta que apunta el .dockitem (si sigue ahi).
#   2. El MISMO archivo buscado por nombre en las carpetas de aplicaciones de
#      siempre (asi sobrevive aunque se haya movido de sitio).
#   3. Si tampoco aparece, uno minimo invented a partir del nombre del
#      lanzador, para que el icono se vea y el lanzador exista al restaurar.
#
# El punto 3 es el que hacia falta: el dock se reconstruye siempre, sin depender
# de que haya un .deb guardado ni de que el .desktop siga en su ruta.
# ─────────────────────────────────────────────────────────────────────────────

# Busca un .desktop por nombre exacto en las carpetas donde vive la de las apps.
# Devuelve la ruta del primero que exista, o nada.
buscar_desktop_por_nombre() {
    local nombre="$1" dir
    [ -n "$nombre" ] || return 0
    for dir in "$APPS_DIR" \
               /usr/share/applications \
               /usr/local/share/applications \
               "$HOME/.local/share/flatpak/exports/share/applications" \
               /var/lib/flatpak/exports/share/applications; do
        [ -d "$dir" ] || continue
        [ -f "$dir/$nombre" ] && { printf '%s\n' "$dir/$nombre"; return 0; }
    done
    return 0
}

# Escribe un .desktop minimo pero VALIDO para que el lanzador no desaparezca.
# Intenta deducir el ejecutable y el icono a partir del nombre del lanzador.
escribir_desktop_minimo() {
    local destino="$1" slug="$2"
    local nombre_visible ejecutable icono cand
    local dir_iconos

    # "jetbrains-idea" -> "jetbrains idea" (algo legible en el dock)
    nombre_visible=$(printf '%s' "$slug" | tr '-' '_' | tr '_' ' ')

    # Ejecutable: el mismo nombre del lanzador, si esta en el PATH
    ejecutable=""
    for cand in "$slug" "${slug%.desktop}"; do
        [ -n "$cand" ] || continue
        ejecutable=$(command -v "$cand" 2>/dev/null) && break
        ejecutable=""
    done

    # Icono: un archivo con ese nombre en cualquier tema de iconos instalado
    icono=""
    for dir_iconos in /usr/share/icons /usr/share/pixmaps "$HOME/.icons" \
                     "$HOME/.local/share/icons" /usr/share/icons/hicolor; do
        [ -d "$dir_iconos" ] || continue
        cand=$(find "$dir_iconos" -maxdepth 3 \( -iname "$slug.*" -o -iname "${slug%.desktop}.*" \) \
               -type f 2>/dev/null | head -1)
        if [ -n "$cand" ]; then icono="$cand"; break; fi
    done

    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$nombre_visible"
        printf 'Comment=Restaurado desde la copia de seguridad de Plank\n'
        [ -n "$ejecutable" ] && printf 'Exec=%s\n' "$ejecutable"
        [ -n "$icono" ]      && printf 'Icon=%s\n' "$icono"
        printf 'Terminal=false\n'
        printf 'NoDisplay=false\n'
        # Sin Exec no se puede arrancar, pero al menos el icono sale. En ese
        # caso se marca para saber que es un launcher reconstruido.
        [ -z "$ejecutable" ] && printf 'X-Mac-Os-Xfce-Reconstruido=true\n'
        return 0
    } > "$destino" 2>/dev/null || true

    chmod +x "$destino" 2>/dev/null || true
}

salvar_recursos_lanzadores() {
    local tmp="$1"
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0

    local rec="$tmp/relaunchers"
    mkdir -p "$rec/icons" "$rec/exec"
    : > "$rec/origen.txt"
    echo "ORIGEN_HOME|$HOME" >> "$rec/origen.txt"

    # ── El ORDEN de los iconos también se guarda ──────────────────────────────
    # Plank no guarda el orden en los .dockitem: lo tiene en dconf
    # (/net/launchpad/plank/docks/dock1/dock-items). Si no se copia aqui, al
    # restaurar en otro PC los iconos salen ordenados por nombre de fichero y
    # el dock queda irreconocible.
    local clave_orden="/net/launchpad/plank/docks/dock1/dock-items"
    if command -v dconf >/dev/null 2>&1; then
        dconf read "$clave_orden" 2>/dev/null \
            | tr -d "[]" | tr ',' '\n' | tr -d " '" | grep -v '^$' \
            > "$rec/orden.txt"
    fi
    [ -s "$rec/orden.txt" ] || ls -1 "$dock"/*.dockitem 2>/dev/null \
        | while read -r f; do basename "$f"; done > "$rec/orden.txt"

    local item ruta ruta_original slug clave valor base destino zip_nom
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        ruta=$(archivo_referido "$item")
        [ -n "$ruta" ] || continue
        ruta="${ruta//\~/$HOME}"

        slug=$(basename "$item" .dockitem)
        [ -n "$slug" ] || slug="launcher"

        # La ruta que apunta el .dockitem se guarda SIEMPRE en origen.txt, aunque
        # luego el archivo se busque en otro sitio o no exista: es lo que deja
        # constancia de de donde venia el lanzador.
        local ruta_original="$ruta"

        # ── El .desktop se copia SIEMPRE ──────────────────────────────────────
        # Antes aqui habia un "[ -f "$ruta" ] || continue": si la ruta guardada
        # en el .dockitem ya no existia, el lanzador se perdia entero y el icono
        # no volvia al restaurar. Y el respaldo de apps no siempre trae .deb
        # (muchos se instalan por PPA o ya no estan en el disco), asi que este
        # .desktop era la unica copia que quedaba.
        #
        # Ahora se resuelve por tres Escalones y SEGURO se guarda algo:
        #   1) la ruta exacta, si sigue ahi
        #   2) el mismo archivo buscado por nombre en las carpetas de siempre
        #   3) si no aparece, uno minimo rebuilt con el nombre del lanzador
        # Pase lo que pase, el .desktop queda en el ZIP y anotado en origen.txt,
        # que es lo que hace que al importar se copie y se re-apunte el dockitem.
        if [ ! -f "$ruta" ]; then
            ruta=$(buscar_desktop_por_nombre "$(basename "$ruta")")
        fi

        if [ -f "$ruta" ]; then
            cp "$ruta" "$rec/${slug}.desktop" 2>/dev/null || \
                escribir_desktop_minimo "$rec/${slug}.desktop" "$slug"
        else
            # No existe en ninguna parte: se anota la ruta original (para que al
            # restaurar se sepa de donde venia) y se inventa el .desktop.
            escribir_desktop_minimo "$rec/${slug}.desktop" "$slug"
        fi

        [ -f "$rec/${slug}.desktop" ] || continue
        echo "DESKTOP|$ruta_original|${slug}.desktop" >> "$rec/origen.txt"

        # Iconos y ejecutables que ese .desktop referencia por ruta absoluta.
        # Se leen de la COPIA GUARDADA, no de la ruta original: asi tambien se
        # guardan bien los recursos cuando el .desktop se reconstruyo (o se
        # copio de otra carpeta), que es justo cuando antes no se guardaba nada.
        for clave in Icon Exec Path; do
            valor=$(grep -m1 "^$clave=" "$rec/${slug}.desktop" 2>/dev/null | cut -d= -f2-)
            [ -n "$valor" ] || continue
            case "$clave" in
                Icon)
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            [ -f "$valor" ] || continue
                            base=$(basename "$valor")
                            if [ ! -f "$rec/icons/$base" ]; then
                                cp "$valor" "$rec/icons/$base" 2>/dev/null || continue
                            fi
                            echo "ICON|$valor|icons/$base" >> "$rec/origen.txt"
                            ;;
                    esac ;;
                Exec)
                    # Los .desktop de JetBrains Toolbox traen el comando ENTRE
                    # comillas: Exec="/home/u/.../apps/idea/bin/idea" %u. Hay que
                    # quitarlas para quedarnos con la ruta real del ejecutable.
                    valor="${valor#\"}"
                    valor="${valor%%\"*}"
                    valor="${valor%% *}"          # solo el comando, sin argumentos
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            [ -f "$valor" ] || continue
                            # Si el ejecutable es en sí mismo una app entera
                            # (los de electron pesan 200 MB o más) no se copia a
                            # ciegas: primero se pregunta de dónde sale. Si se
                            # sabe, su .deb o su propia app ya viajan en el
                            # respaldo y copiarlo aquí solo duplicaría la app.
                            # Si NO se sabe, se copia siempre, sin límite: mejor
                            # un ejecutable de más que perder la aplicación.
                            if [ "$(du -m "$valor" 2>/dev/null | cut -f1)" -gt "$LIMITE_EJECUTABLE_MB" ]; then
                                _capa=$(dirname "$valor")
                                _tr=$(detectar_reinstalacion "$_capa" "$(basename "$_capa")")
                                _t="${_tr%%|*}"
                                _d="${_tr#*|}"; _d="${_d%%|*}"
                                if reinstalacion_fiable "$_t" "$_d"; then
                                    n_recurso_grande=$(( ${n_recurso_grande:-0} + 1 ))
                                    continue
                                fi
                            fi
                            zip_nom=$(echo "$valor" | sed "s|^$HOME/||")
                            [ -n "$zip_nom" ] || zip_nom=$(basename "$valor")
                            mkdir -p "$rec/exec/$(dirname "$zip_nom")"
                            if [ ! -f "$rec/exec/$zip_nom" ]; then
                                cp "$valor" "$rec/exec/$zip_nom" 2>/dev/null || continue
                            fi
                            echo "Exec|$valor|exec/$zip_nom" >> "$rec/origen.txt"
                            ;;
                    esac ;;
                Path)
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            if [ ! -f "$valor" ] && [ ! -d "$valor" ]; then continue; fi
                            zip_nom=$(echo "$valor" | sed "s|^$HOME/||")
                            [ -n "$zip_nom" ] || zip_nom=$(basename "$valor")
                            mkdir -p "$rec/path/$(dirname "$zip_nom")"
                            if [ ! -e "$rec/path/$zip_nom" ]; then
                                cp -r "$valor" "$rec/path/$zip_nom" 2>/dev/null || continue
                            fi
                            echo "Path|$valor|path/$zip_nom" >> "$rec/origen.txt"
                            ;;
                    esac ;;
            esac
        done
    done
}

restaurar_recursos_lanzadores() {
    local tmp="$1"
    local dock="$PLANK_CONFIG/dock1/launchers"
    local rec="$tmp/relaunchers"
    [ -d "$rec" ] || return 0

    # Hogar del PC de ORIGEN (guardado en el mapa): sirve para traducir las
    # rutas absolutas hacia el hogar de ESTE PC, sea cual sea el prefijo
    # (no solo /home/...), aunque el usuario cambie de nombre o de disco.
    local origin_home=""
    while IFS='|' read -r tipo rest1 rest2; do
        if [ "$tipo" = "ORIGEN_HOME" ]; then origin_home="$rest1"; break; fi
    done < "$rec/origen.txt"

    # ── 1) Colocar los .desktop guardados en ~/.local/share/applications ──
    mkdir -p "$APPS_DIR"
    local f nom destino
    for f in "$rec"/*.desktop; do
        [ -f "$f" ] || continue
        nom=$(basename "$f")
        destino="$APPS_DIR/$nom"
        if [ "$modo" = "Reemplazar" ] || [ ! -e "$destino" ]; then
            cp -f "$f" "$destino"
            chmod +x "$destino" 2>/dev/null || true
        fi
        # Corregir las rutas absolutas de ESTE .desktop (Icon, Exec, Path)
        if [ -n "$origin_home" ]; then
            sed -i "s|$origin_home|$HOME|g" "$destino" 2>/dev/null || true
        else
            sed -i "s|/home/[^/]*/|/home/$USER/|g" "$destino" 2>/dev/null || true
        fi
    done

    # ── 2) Recolocar iconos / ejecutables / carpetas a su ruta en ESTE PC,
    #        traduciendo el home de origen por el actual ──
    # Para los destinos FUERA de $HOME que son de solo-root (p. ej.
    # /usr/local/bin/virtualbox-no-kvm, el script que lanza el VirtualBox
    # recién instalado por apt), si la copia como usuario no puede, se
    # reintenta con sudo -n (funciona si la regla visudo ya está instalada).
    _colocar_recurso() {
        local _src="$1" _dst="$2" _dd
        _dd=$(dirname "$_dst")
        mkdir -p "$_dd" 2>/dev/null || true
        if ! cp -r "$_src" "$_dst" 2>/dev/null; then
            sudo -n mkdir -p "$_dd" 2>/dev/null
            sudo -n cp -r "$_src" "$_dst" 2>/dev/null || true
        fi
    }
    local tipo ruta_origen zip_rel ruta_nueva
    while IFS='|' read -r tipo ruta_origen zip_rel; do
        [ -n "$tipo" ] || continue
        case "$tipo" in
            ICON|Exec|Path)
                if [ -n "$origin_home" ]; then
                    ruta_nueva="${ruta_origen/#$origin_home/$HOME}"
                else
                    ruta_nueva=$(echo "$ruta_origen" | sed "s|/home/[^/]*/|/home/$USER/|g")
                fi
                if [ -e "$rec/$zip_rel" ]; then
                    if [ "$tipo" = "Path" ] && [ -d "$rec/$zip_rel" ]; then
                        # carpeta completa: crear y copiar SOLO lo que falte
                        # (sin pisar nada que ya exista en este PC)
                        if ! { mkdir -p "$ruta_nueva" 2>/dev/null && cp -rn "$rec/$zip_rel"/. "$ruta_nueva" 2>/dev/null; }; then
                            sudo -n mkdir -p "$ruta_nueva" 2>/dev/null
                            sudo -n cp -rn "$rec/$zip_rel"/. "$ruta_nueva" 2>/dev/null || true
                        fi
                    elif [ ! -e "$ruta_nueva" ]; then
                        # archivo suelto: solo si todavía no existe
                        _colocar_recurso "$rec/$zip_rel" "$ruta_nueva"
                    fi
                    if [ -e "$ruta_nueva" ]; then
                        chmod +x "$ruta_nueva" 2>/dev/null || sudo -n chmod +x "$ruta_nueva" 2>/dev/null || true
                    fi
                fi
                ;;
        esac
    done < "$rec/origen.txt"

    # ── 3) Reescribir .dockitem: si la ruta apuntada NO existe aquí, o existe
    #        pero NO es idéntica a la que guardaste (p. ej. el .desktop del
    #        sistema fue actualizado o lo modificaste a mano), se redirige al
    #        .desktop restaurado → funciona IGUAL que en el PC de origen ──
    local item ruta_iter slug usado
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        ruta_iter=$(archivo_referido "$item")
        [ -n "$ruta_iter" ] || continue
        ruta_iter="${ruta_iter//\~/$HOME}"
        if [ -n "$origin_home" ]; then
            ruta_iter="${ruta_iter/#$origin_home/$HOME}"
        else
            ruta_iter=$(echo "$ruta_iter" | sed "s|/home/[^/]*/|/home/$USER/|g")
        fi

        slug=$(basename "$item" .dockitem)
        usado="$APPS_DIR/$slug.desktop"
        if [ ! -f "$usado" ]; then
            usado=""
            while IFS='|' read -r tipo ruta_origen zip_rel; do
                if [ "$tipo" = "DESKTOP" ] && [ "${zip_rel%.desktop}" = "$slug" ]; then
                    usado="$APPS_DIR/$zip_rel"
                    break
                fi
            done < "$rec/origen.txt"
        fi
        [ -f "$usado" ] || continue   # sin copia guardada: se deja como esté

        if [ -f "$ruta_iter" ]; then
            # La ruta original existe: solo se re-apunta si difiere del guardado
            cmp -s "$ruta_iter" "$usado" && continue
        fi
        printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$usado" > "$item"
    done
}

# ─── Paquetes apt detrás de cada lanzador ─────────────────────────────────────
# Un lanzador del dock casi nunca es “un paquete directo”: el .desktop real
# suele vivir en ~/.local/share/applications (propio, sin dueño en dpkg) y
# apuntar a un wrapper o al binario instalado por su paquete (VS Code,
# Docker Desktop, Unity Hub…). Para descubrir el paquete “de verdad”:
#   1) ¿dpkg es dueño del .desktop?            (los del sistema: sí)
#   2) si no, ¿qué binario REAL ejecuta Exec?  (args fuera, symlinks dentro)
#   3) si ese binario es un wrapper propio (~/.local/bin, ~/Aplicaciones…),
#      se buscan las rutas absolutas a las que apunta dentro (Docker, Unity…)
# Se descartan paquetes “de infraestructura” (bash, python3, coreutils…)
# que jamás son la app que se ancla en el dock.

paquete_basura() {  # ¿paquete de sistema que no es “la app”? → no listar
    case "$1" in
        bash|dash|sh|coreutils|util-linux|procps|grep|sed|awk|gawk|mawk|diffutils|findutils|patch|tar|gzip|xz-utils|bzip2|dpkg|apt|perl|perl-base|python3|python3-minimal|python3.1*|libc6|init-system-helpers|debianutils|base-files|base-passwd|bsdutils|passwd|login|mint-meta-core|mint-meta-xfce)
            return 0 ;;
        *) return 1 ;;
    esac
}

binarios_de_desktop() {  # binario(s) REAL(es) que lanza un .desktop
    local desk="$1" linea cmd ruta cand
    linea=$(sed -n 's/^Exec=//p' "$desk" | head -1 | tr -d '\r')
    [ -n "$linea" ] || return 0
    cmd=$(echo "$linea" | awk '{print $1}')
    [ "$cmd" = "env" ] && cmd=$(echo "$linea" | awk '{print $2}')
    [ -z "$cmd" ] && return 0
    cmd="${cmd//\"/}"
    case "$cmd" in
        /*) ruta="$cmd" ;;
        *)  ruta=$(command -v "$cmd" 2>/dev/null) || return 0 ;;
    esac
    [ -f "$ruta" ] || return 0
    ruta=$(readlink -f "$ruta" 2>/dev/null || echo "$ruta")
    echo "$ruta"
    # ¿Es un wrapper propio (script)? Los de Docker Desktop, Unity Hub…
    # apuntan dentro a la ruta real (/opt/…, /usr/lib/…): exponerla también.
    if [ "$(head -c 2 "$ruta" 2>/dev/null)" = "#!" ]; then
        case "$ruta" in
            "$HOME"/.local/bin/*|"$HOME"/Aplicaciones/*|"$HOME"/bin/*)
                while IFS= read -r cand; do
                    [ -f "$cand" ] && [ -x "$cand" ] && echo "$cand"
                done < <(grep -oE '/(opt|usr/lib|usr/share|usr/local)[^ "]+' "$ruta" 2>/dev/null | sort -u) ;;
        esac
    fi
}

# Paquetes de las aplicaciones ancladas en el dock/navbar de Plank
paquetes_navbar() {
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0
    local item archivo pkg binario
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        archivo=$(archivo_referido "$item")
        [ -n "$archivo" ] || continue
        archivo="${archivo//\~/$HOME}"
        [ -f "$archivo" ] || continue

        # 1) ¿El .desktop es de un paquete? (los del sistema, sí)
        pkg=$(dpkg -S "$archivo" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$pkg" ] && ! paquete_basura "$pkg"; then
            echo "$pkg"
            continue
        fi

        # 2) El .desktop es propio: rastrear el binario REAL y su wrapper
        for binario in $(binarios_de_desktop "$archivo"); do
            pkg=$(dpkg -S "$binario" 2>/dev/null | head -1 | cut -d: -f1)
            if [ -n "$pkg" ] && ! paquete_basura "$pkg"; then
                echo "$pkg"
                break
            fi
        done
    done | sort -u
}

# ─── Orden de los lanzadores en el dock (dconf dock-items) ─────────────────────
# El orden real de Plank NO está en los archivos .dockitem: vive en dconf,
# en /net/launchpad/plank/docks/dock1/dock-items. Si Plank está corriendo
# mientras se restaura, él mismo vuelve a escribir esa clave con su estado
# en memoria y PISA el orden restaurado. Por eso:
#   • al importar se PARA Plank antes de tocar nada (plank_importar), y
#   • esta función asegura que la lista dconf contenga TODOS los dockitem
#     existentes, respetando el orden actual y añadiendo al final los que
#     falten (p. ej. los nuevos lanzadores en modo “Mezclar”).
#
# Si se le pasa un fichero de orden (el orden.txt que va en el respaldo), manda
# ese: así el dock de un PC nuevo sale igual que el del PC viejo.
orden_dock_asegurar() {
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0
    command -v dconf >/dev/null 2>&1 || return 0
    local clave="/net/launchpad/plank/docks/dock1/dock-items"
    local lista=() actual item f base ya i contenido

    actual=$(dconf read "$clave" 2>/dev/null)
    if [ -n "$1" ] && [ -f "$1" ]; then
        # Orden que venía en el respaldo: manda sobre el de ahora.
        local q="" it
        while IFS= read -r it; do
            [ -z "$it" ] && continue
            it="${it//\'/\\\'}"
            q+="${q:+, }'$it'"
        done < "$1"
        actual="[$q]"
    fi

    if [ -n "$actual" ] && [[ "$actual" == \[* ]]; then
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            [ -f "$dock/$item" ] && lista+=("$item")
        done < <(echo "$actual" | tr -d '[]' | tr ',' '\n' | tr -d " '")
    fi
    for f in "$dock"/*.dockitem; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        ya=0
        for i in "${lista[@]}"; do [ "$i" = "$base" ] && ya=1 && break; done
        [ "$ya" -eq 0 ] && lista+=("$base")
    done
    [ "${#lista[@]}" -eq 0 ] && return 0
    contenido=$(printf "'%s', " "${lista[@]}")
    contenido="[${contenido%, }]"
    dconf write "$clave" "$contenido"
}

# Qué se va a guardar. La configuración del dock, los lanzadores, las apps, los
# scripts, el autostart y los iconos van SIEMPRE en el respaldo: lo que se elige
# son las LISTAS DE PAQUETES. Por eso arrancan en "true" y las dos únicas
# banderas que se tocan son f_navbar y f_manuales.
f_config=true f_apps=true f_scripts=true f_autostart=true f_iconos=true
f_navbar=false f_manuales=false

# URL del .deb de un paquete sin repo, para que instalar.sh lo vuelva a
# bajar en el otro PC (viaja el ENLACE, no la app). Fuentes:
#   1) Historial real de descargas de este PC (Firefox, Chrome/Chromium,
#      Brave, Edge y terminal: .bash_history / .zsh_history).
#   2) Enlaces estables de "última versión" que publica el propio fabricante
#      (el historial solo guarda la URL concreta de ese día).
url_deb_de() {
    local paq="$1" fuente u
    for fuente in ~/.mozilla/firefox/*/places.sqlite \
                  ~/.config/google-chrome/*/History \
                  ~/.config/chromium/*/History \
                  ~/.config/BraveSoftware/*/History \
                  ~/.config/microsoft-edge/*/History \
                  ~/.bash_history ~/.zsh_history; do
        [ -f "$fuente" ] || continue
        u=$(grep -aoE "https?://[^\"<> ]*${paq}[^\"<> ]*\\.deb" "$fuente" 2>/dev/null | head -1 | sed 's/\(\.deb\).*/\1/')
        [ -n "$u" ] && { echo "$u"; return 0; }
    done
    case "$paq" in
        docker-desktop) echo "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb" ;;
        ulauncher)      echo "https://github.com/Ulauncher/Ulauncher/releases/download/5.16.2/ulauncher_5.16.2_all.deb" ;;
    esac
}

# URL de un archivo de app portátil (tar.gz, AppImage…) desde el historial.
# Complementa a url_deb_de para las apps que NO se instalan con apt.
url_archivo_de() {
    local app="$1" fuente u
    for fuente in ~/.mozilla/firefox/*/places.sqlite \
                  ~/.config/google-chrome/*/History \
                  ~/.config/chromium/*/History \
                  ~/.config/BraveSoftware/*/History \
                  ~/.config/microsoft-edge/*/History \
                  ~/.bash_history ~/.zsh_history; do
        [ -f "$fuente" ] || continue
        u=$(grep -aoE "https?://[^\"<> ]*${app}[^\"<> ]*\\.(tar\\.gz|tar\\.xz|tar\\.bz2|tgz|tar\\.zst|zip|AppImage)" "$fuente" 2>/dev/null | head -1 | sed 's/\(\.tar\.gz\|\.tar\.xz\|\.tar\.bz2\|\.tgz\|\.tar\.zst\|\.zip\|\.AppImage\).*/\1/')
        [ -n "$u" ] && { echo "$u"; return 0; }
    done
    return 0
}

# Contenedor root de una app portátil bajo $HOME (vacío si no aplica):
# ~/Aplicaciones, ~/Software, ~/Programas, ~/Programs, apps del Toolbox…
contenedor_portatil() {
    local p="$1" d
    d=$(dirname "$p")
    while [ "$d" != "/" ]; do
        case "$d" in
            "$HOME"/Aplicaciones|"$HOME"/Software|"$HOME"/Programas|"$HOME"/Programs|\
            "$HOME"/.local/share/JetBrains/Toolbox/apps|"$HOME"/opt)
                echo "$d"; return 0 ;;
        esac
        d=$(dirname "$d")
    done
    return 0
}

# Carpeta concreta de la app dentro del contenedor. P. ej. con
# .../Aplicaciones/jetbrains-toolbox-3.8.1.88030/bin/x devuelve
# .../Aplicaciones/jetbrains-toolbox-3.8.1.88030 (donde se extrae su tar.gz).
app_dir_de() {
    local p="$1" d
    d=$(dirname "$p")
    while [ "$d" != "/" ]; do
        case "$d" in
            "$HOME"/Aplicaciones|"$HOME"/Software|"$HOME"/Programas|"$HOME"/Programs|\
            "$HOME"/.local/share/JetBrains/Toolbox/apps|"$HOME"/opt)
                echo "$p"; return 0 ;;
        esac
        p="$d"; d=$(dirname "$d")
    done
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Apps enormes: NO se descartan, se reconstruyen
#
# Copiar 4,3 GB de IntelliJ + 3,6 GB de PyCharm + 3,5 GB de Android Studio
# convertía el respaldo del dock en 12 GB y media hora de espera. Pero la
# solución NO puede ser "no se copia nada": si no se sabe de dónde sale una
# app, perderla no es una opción. Por eso aquí solo se guarda CÓMO volver a
# obtenerla, y eso se deduce dinámicamente, sin inventar una tabla de nombres:
#
#   1) API pública de JetBrains. Cada app de JetBrains lleva dentro un
#      product-info.json con su código de producto y su build. Con eso se le
#      pregunta a JetBrains por el archivo de Linux de ESE build, y se
#      comprueba que coincide exactamente. No hace falta el Toolbox.
#   2) Los ficheros del Toolbox (state.json + channels/<id>.json), que traen
#      el downloadUrl oficial. Fuente opcional: si no hay Toolbox, se sigue.
#   3) El historial de descargas de este PC.
#   4) Los metadatos que la propia app declara (app-update.yml de Electron).
#   5) snap, flatpak, apt o un .deb suyo por el disco.
#
# Y si ninguna de esas encaja, la app se COPIA ENTERA, sin tope de tamaño:
# mejor un respaldo grande que perder una aplicación.
#
# Lo que se guarda en mapa.txt:
#   REINSTALL|<app>|<tipo>|<dato>|<versión>|<MB>|<carpeta destino>
#   tipo = url | apt | snap | flatpak | gh | deb
# ─────────────────────────────────────────────────────────────────────────────

TOOLBOX_DIR="$HOME/.local/share/JetBrains/Toolbox"

# El ayudante va DENTRO del script a proposito: plank-backup.sh se copia
# suelto a ~/.local/bin (lo hacen panel.sh y nautilus.sh) y se lanza desde el
# dock. Si dependiera de un toolbox.py hermano, en el PC del usuario no
# existiria y el respaldo de apps grandes se caeria al vacio.
_toolbox_py() {
    local modo="$1"; shift
    python3 - "$modo" "$@" <<'FINTB'
import json
import re
import sys

def carga(ruta):
    with open(ruta, encoding="utf-8") as f:
        return json.load(f)

def datos(state_path, carpeta):
    """channelId|version|toolId de la app instalada en 'carpeta'.

    Se busca por la CARPETA de instalacion, que es el unico dato que hace
    falta: no hay que saber como se llama ninguna app.
    """
    try:
        blob = carga(state_path)
    except Exception:
        return ""
    for t in blob.get("tools", []) or []:
        loc = (t.get("installLocation") or "").rstrip("/")
        if not loc.endswith("/" + carpeta):
            continue
        # Android Studio llega como "Quail 4 2026.1.4 Patch 1" y hay que
        # quedarse con "2026.1.4": se busca el primer trozo con forma de
        # version, no "el primer numero" (que seria el 4 del codename).
        version = t.get("displayVersion") or ""
        encontrado = re.search(r"\d+(?:\.\d+)+", version)
        if encontrado:
            version = encontrado.group(0)
        return "%s|%s|%s" % (t.get("channelId") or "", version,
                             t.get("toolId") or "")
    return ""

def url(canal_path):
    """Mejor URL de descarga para Linux dentro del JSON de un canal.

    Se recorre el JSON entero y se elige el enlace que apunte a un binario de
    Linux, sin mirar el nombre de la app.
    """
    try:
        doc = carga(canal_path)
    except Exception:
        return ""
    candidatas = []

    def recorre(o):
        if isinstance(o, dict):
            for clave, valor in o.items():
                if isinstance(valor, (dict, list)):
                    recorre(valor)
                elif isinstance(valor, str) and valor.startswith("http"):
                    if re.search(r"downloadurl|download_url|linuxlink", clave, re.I) \
                            or re.search(r"\.(tar\.gz|tar\.xz|zip|dmg|deb|rpm)(\?.*)?$",
                                         valor, re.I):
                        candidatas.append((clave, valor))
        elif isinstance(o, list):
            for v in o:
                recorre(v)

    recorre(doc)
    if not candidatas:
        return ""
    # 1) el campo que el propio canal marca como Linux
    for clave, valor in candidatas:
        if "linux" in clave.lower():
            return valor
    # 2) el enlace de descarga cuyo archivo lleva "linux" en el nombre
    for clave, valor in candidatas:
        if "linux" in valor.lower():
            return valor
    # 3) el primer downloadUrl que aparezca
    for clave, valor in candidatas:
        if "downloadurl" in clave.lower():
            return valor
    return ""

def jinfo(ruta):
    """codigo|build|version de lo que una app JetBrains declara de si misma.

    product-info.json es el archivo que lleva dentro TODO producto de
    JetBrains (IntelliJ, PyCharm, WebStorm, Rider, GoLand...), y dice su
    codigo de producto y su build sin depender del Toolbox ni de su nombre.
    """
    try:
        doc = carga(ruta)
    except Exception:
        return ""
    return "%s|%s|%s" % (doc.get("productCode") or "",
                         doc.get("buildNumber") or "",
                         doc.get("version") or "")

def jetbrains(codigo, build, version):
    """URL de descarga para Linux de una app JetBrains, por su API publica.

    Se le pide a JetBrains el HISTORICO COMPLETO de versiones del producto y se
    busca la que lleva EXACTAMENTE el mismo build que el de la app instalada.
    No se mira el nombre de la app en ningun momento: solo su codigo, que la
    propia app declara.

    Si ese build no aparece en la lista, se devuelve "" a proposito: mejor copiar
    4 GB enteros que apuntar a una URL que podria ser otra version.
    """
    import urllib.parse
    import urllib.request
    consulta = ("https://data.services.jetbrains.com/products/releases?code=%s"
                "&type=release&latest=false" % urllib.parse.quote(codigo))
    try:
        with urllib.request.urlopen(consulta, timeout=25) as f:
            doc = json.loads(f.read().decode("utf-8", "replace"))
    except Exception:
        return ""
    for lista in (doc or {}).values():
        for r in lista or []:
            if not isinstance(r, dict):
                continue
            if build and str(r.get("build") or "") == str(build):
                enlace = ((r.get("downloads") or {}).get("linux") or {}).get("link")
                if enlace:
                    return enlace
            elif not build and version and str(r.get("version") or "") == str(version):
                enlace = ((r.get("downloads") or {}).get("linux") or {}).get("link")
                if enlace:
                    return enlace
    return ""

modo = sys.argv[1]
if modo == "datos":
    print(datos(sys.argv[2], sys.argv[3]))
elif modo == "url":
    print(url(sys.argv[2]))
elif modo == "jinfo":
    print(jinfo(sys.argv[2]))
elif modo == "jetbrains":
    print(jetbrains(sys.argv[2], sys.argv[3], sys.argv[4]))
FINTB
}

# Datos de una app del Toolbox: channelId|version|toolId, leidos de state.json.
toolbox_datos_de() {
    local nombre="$1"
    [ -n "$nombre" ] && [ -f "$TOOLBOX_DIR/state.json" ] || return 1
    _toolbox_py datos "$TOOLBOX_DIR/state.json" "$nombre"
}

# URL de descarga REAL de un canal del Toolbox, tal cual la trae su ficha.
toolbox_url_canal() {
    local canal="$1"
    [ -n "$canal" ] && [ -f "$TOOLBOX_DIR/channels/$canal.json" ] || return 1
    _toolbox_py url "$TOOLBOX_DIR/channels/$canal.json"
}

# ── Apps de JetBrains, resueltas por su API publica ───────────────────────────
# Estas NO hacen falta para el Toolbox: la propia app lleva dentro un
# product-info.json con su codigo de producto y su build, y la API publica de
# JetBrains devuelve el archivo de Linux de ese build exacto. Se comprueba que
# el build coincide; si no, la app se copia entera.
jetbrains_info() {
    local dir="$1" f
    [ -d "$dir" ] || return 1
    f=$(find "$dir" -maxdepth 3 -type f -name 'product-info.json' 2>/dev/null | head -1)
    [ -n "$f" ] || return 1
    _toolbox_py jinfo "$f"
}

jetbrains_url() {
    local codigo="$1" build="$2" version="$3"
    [ -n "$codigo" ] || return 1
    _toolbox_py jetbrains "$codigo" "$build" "$version"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cómo se vuelve a conseguir UNA APP, sea la que sea y aunque no sepamos nada
# de ella. Se va mirando de donde sale hasta que algo encaja, y el Toolbox es
# solo UNA de las fuentes: si no lo hay, se sigue buscando por otros lados.
#
# Devuelve "tipo|dato|version":
#   art|<fichero>        es un AppImage suelto en su carpeta: se copia
#   url|<url>|<version>  tenemos su URL de descarga exacta (API de JetBrains,
#                        Toolbox, historial…). Si viene con versión, se anota
#   gh|<dueño/repo>      la app dice en sus propios metadatos de qué GitHub
#                        sale (las de Electron llevan app-update.yml): se
#                        pregunta a la API y se baja la última versión
#   deb|<fichero .deb>   se instalo con un .deb suyo, baixado a mano
#   apt|<paquete>        existe como paquete de Debian/Ubuntu con ese nombre
#   snap|<nombre>        vive en /snap
#   flatpak|<id>         se la pregunta al propio flatpak (sin adivinar el id)
#   manual|              no hay ninguna forma automática
#
# No hay tablas de nombres: todo se deduce de la ruta, del nombre de la carpeta,
# de lo que la app declara de sí misma y de lo que responden apt/flatpak.
# ─────────────────────────────────────────────────────────────────────────────
detectar_reinstalacion() {
    local dir="$1" base="$2"
    local _cand _id _ai _yml _prov _url _owner _repo _info _ver
    local _codigo _build _version _deb

    # 1) AppImage suelto dentro de su propia carpeta: pesa poco y se copia tal
    #    cual, que es mejor que cualquier URL.
    if [ -d "$dir" ]; then
        _ai=$(find "$dir" -maxdepth 2 -type f -iname '*.AppImage' 2>/dev/null | head -1)
        [ -n "$_ai" ] && { echo "art|$(basename "$_ai")"; return 0; }
    fi

    # 2) Apps de JetBrains (IntelliJ, PyCharm, WebStorm, Rider, GoLand…): se
    #    leen su product-info.json, que es suyo, y con su codigo y su build se
    #    pregunta a la API publica de JetBrains por el archivo de Linux de ESA
    #    version exacta. No hace falta el Toolbox ni saber el nombre de la app.
    if [ -d "$dir" ]; then
        _info=$(jetbrains_info "$dir" 2>/dev/null)
        if [ -n "$_info" ]; then
            _codigo=$(printf '%s' "$_info" | cut -d'|' -f1)
            _build=$(printf '%s' "$_info" | cut -d'|' -f2)
            _version=$(printf '%s' "$_info" | cut -d'|' -f3)
            _url=$(jetbrains_url "$_codigo" "$_build" "$_version" 2>/dev/null)
            if [ -n "$_url" ]; then
                echo "url|$_url|$_version ($_build)"
                return 0
            fi
        fi
    fi

    # 3) El Toolbox, si es una app suya: guarda su URL oficial ya resuelta en
    #    sus ficheros de canal. Fuente opcional: si no hay Toolbox, se sigue.
    if [ -n "${TOOLBOX_DIR:-}" ] && [ -d "$TOOLBOX_DIR" ]; then
        _info=$(toolbox_datos_de "$(basename "$dir")" 2>/dev/null)
        if [ -n "$_info" ]; then
            _url=$(toolbox_url_canal "$(printf '%s' "$_info" | awk -F'|' '{print $1}')" 2>/dev/null)
            [ -n "$_url" ] && { echo "url|$_url|$(printf '%s' "$_info" | awk -F'|' '{print $2}')"; return 0; }
        fi
    fi

    # 4) Historial real de descargas de este PC (Firefox, Chrome, Brave, Edge,
    #    terminal). No necesita saber nada de la app: busca su nombre.
    _url=$(url_archivo_de "$base" 2>/dev/null)
    [ -n "$_url" ] && { echo "url|$_url|"; return 0; }

    # 5) Que la app diga de donde sale. Las de Electron (Discord, VS Code,
    #    Obsidian…) dejan app-update.yml con su proveedor y su repositorio:
    #    con eso se reconstruye la descarga sin conocer la app.
    _yml=$(find "$dir" -maxdepth 4 -type f \( -name 'app-update.yml' -o -name 'app-update.yaml' \) 2>/dev/null | head -1)
    if [ -n "$_yml" ]; then
        _prov=$(grep -m1 '^[[:space:]]*provider:' "$_yml" 2>/dev/null | cut -d: -f2- | tr -d " \r'\"")
        _url=$(grep -m1 '^[[:space:]]*url:' "$_yml" 2>/dev/null | cut -d: -f2- | tr -d " \r'\"")
        _owner=$(grep -m1 '^[[:space:]]*owner:' "$_yml" 2>/dev/null | cut -d: -f2- | tr -d " \r'\"")
        _repo=$(grep -m1 '^[[:space:]]*repo:' "$_yml" 2>/dev/null | cut -d: -f2- | tr -d " \r'\"")
        # Ojo: aquí el campo url: de un app-update.yml con provider "generic"
        # NO es el archivo que hay que bajar, es el servidor donde se PUBLICA
        # (la API de actualizaciones). Solo se acepta si además parece un
        # fichero de verdad; si no, se sigue buscando por otros lados.
        if [ -n "$_url" ] && url_es_fichero "$_url"; then
            echo "url|$_url|"; return 0
        fi
        if [ "$_prov" = "github" ] && [ -n "$_owner" ] && [ -n "$_repo" ]; then
            echo "gh|$_owner/$_repo|ultima"; return 0
        fi
    fi

    # 6) Un instalador .deb suyo por el disco. Muchas apps no están en ningún
    #    repositorio y se instalan con un .deb bajado a mano (opencode,
    #    docker-desktop, ulauncher…). No hay que saber nada de la app: se
    #    busca un .deb cuyo nombre contenga el suyo, y si está, ese fichero
    #    es la app. Al importar se instala con un "apt install ./archivo.deb".
    if [ -n "$base" ]; then
        _deb=$(find "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio" \
               "$HOME/.cache" "$HOME/.local/share" \
               -maxdepth 3 -type f -iname "*${base}*.deb" 2>/dev/null | head -1)
        [ -n "$_deb" ] && { echo "deb|$_deb|$(basename "$_deb")"; return 0; }
    fi

    # 7) snap: /snap/<nombre>/<version>/...
    case "$dir" in
        /snap/*)
            _cand=$(printf '%s' "$dir" | cut -d/ -f3)
            [ -n "$_cand" ] && { echo "snap|$_cand|"; return 0; }
            ;;
    esac

    # 7) flatpak: se pregunta al flatpak, no se adivina el identificador.
    if command -v flatpak >/dev/null 2>&1; then
        _id=$(flatpak list --app --columns=application 2>/dev/null \
              | grep -i "/$base\." | head -1)
        [ -n "$_id" ] && { echo "flatpak|$_id|"; return 0; }
    fi

    # 8) paquete de Debian/Ubuntu con ese nombre, con y sin guiones (muchas
    #    apps se llaman en el repositorio sin guiones: heidisql, 7zip…).
    if command -v apt-cache >/dev/null 2>&1; then
        for _cand in "$base" "$(printf '%s' "$base" | tr -d '-')"; do
            [ -n "$_cand" ] || continue
            apt-cache show "$_cand" >/dev/null 2>&1 && { echo "apt|$_cand|"; return 0; }
        done
    fi

    echo "manual|"
}

# ¿Esa URL existe de verdad ahora mismo? Se le pregunta al servidor. Solo se
# usa para URLs: los repos de apt, los snaps, los flatpaks y los AppImage no
# necesitan comprobacion (o son un fichero local, o los verifica su propio
# gestor al instalar). Comprobarlo evita apuntar a un enlace caducado y perder
# una app de 4 GB porque su URL dejo de existir.
url_responde() {
    local u="$1" codigo
    [ -n "$u" ] || return 1
    if command -v curl >/dev/null 2>&1; then
        # Primero HEAD, que es lo más barato. Pero hay servidores que no lo
        # admiten, así que si HEAD no vale se pregunta con un GET de un solo
        # byte: funciona en todas partes y no baja la app entera.
        codigo=$(curl -sIL --max-time 12 -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
        case "$codigo" in
            200|201|206|301|302|303|307|308) return 0 ;;
        esac
        codigo=$(curl -s -r 0-0 --max-time 12 -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        wget --spider -q --timeout=12 --tries=1 "$u" >/dev/null 2>&1 && codigo=200 || codigo=0
    else
        # Sin curl ni wget no se puede comprobar: se supone que vale.
        return 0
    fi
    case "$codigo" in
        200|201|206|301|302|303|307|308) return 0 ;;
        *) return 1 ;;
    esac
}

# ¿Esa URL apunta a un FICHERO que se puede bajar, o es una página de la que
# hay que sacarlo? Importa mucho: el historial y el app-update.yml de Electron
# también guardan URLs que solo son consultar (la API de actualizaciones de
# una app, por ejemplo), que responden 200 pero bajan un JSON, no la app.
# Apuntar a una de esas y darla por buena haria que al importar se bajase
# basura en lugar de la aplicación.
url_es_fichero() {
    local u="$1"
    printf '%s' "${u%%[?#]*}" \
        | grep -qiE '\.(tar\.gz|tar\.xz|tar\.bz2|tar\.zst|tgz|zip|7z|rar|dmg|pkg|deb|rpm|snap|flatpak|appimage|exe|msi|run)$'
}

# ─────────────────────────────────────────────────────────────────────────────
# ¿Se puede recuperar ESTA app de forma fiable con lo que ha detectado
# detectar_reinstalacion?
#
# aqui no hay ningun tamano de por medio: la pregunta es solo de confianza.
#   art / apt / snap / flatpak -> si, el sistema o el propio fichero lo dan
#   deb                       -> si, es un .deb del que hay copia en el
#                                respaldo (se instala con apt install ./…
#                                y arrastra sus dependencias)
#   gh                         -> si, la API de GitHub dira que archivo es
#   url                        -> solo si es un fichero real Y responde ahora
#   manual                     -> NO se sabe: hay que copiarla entera
# ─────────────────────────────────────────────────────────────────────────────
reinstalacion_fiable() {
    local tipo="$1" dato="$2"
    case "$tipo" in
        art|deb|apt|snap|flatpak|gh) return 0 ;;
        url)                     url_es_fichero "$dato" && url_responde "$dato" ;;
        *)                       return 1 ;;
    esac
}
# ─────────────────────────────────────────────────────────────────────────────
# Según lo que HAYA, para cada app portátil (JetBrains Toolbox, HeidiSQL…):
#   - si su archivo original (tar.gz/AppImage…) sigue en el disco → viaja;
#   - si no, viaja la URL de donde se descargó (historial de descargas);
#   - si NO se sabe de qué URL viene y no queda el archivo, viaja su carpeta
#     entera (única forma de que funcione en el otro PC).
# en el otro PC, instalar.sh decide: extrae el archivo, baja la URL o,
# si venía la carpeta, la recoloca. (Se llama DESPUÉS de
# salvar_recursos_lanzadores, porque usa relaunchers/origen.txt para saber
# dónde vivía cada app.)
salvar_artefactos_origen() {
    local tmp="$1"
    local rec="$tmp/relaunchers"
    local ori="$tmp/paquetes/origen"
    local pkgs ad base arch u cont dir
    pkgs=$(cat "$tmp/paquetes/navbar.txt" "$tmp/paquetes/manuales.txt" 2>/dev/null | sort -u | tr '\n' ' ')
    [ -d "$rec" ] || return 0

    # (1) carpetas de apps portátiles que los lanzadores usan por ruta
    local appdirs="" tipo ruta
    while IFS='|' read -r tipo ruta _; do
        [ "$tipo" = "Exec" ] || [ "$tipo" = "ICON" ] || continue
        [ -n "$ruta" ] || continue
        # No se descartan las rutas bajo $HOME/.local: los ejecutables de las apps
        # del JetBrains Toolbox viven en ~/.local/share/JetBrains/Toolbox/apps/*
        # (contenedor_portatil decide si una ruta es o no una app portátil).
        case "$ruta" in /usr/*|/opt/*) continue;; esac
        cont=$(contenedor_portatil "$ruta") || continue
        [ -n "$cont" ] || continue
        dir=$(app_dir_de "$ruta") || continue
        [ -n "$dir" ] || continue
        case " $appdirs " in *" $dir "*) continue;; esac
        appdirs="$appdirs $dir"
    done < "$rec/origen.txt"

    [ -n "$appdirs" ] || return 0
    mkdir -p "$ori"

    # (2) por cada app: archivo original en disco, o su URL de descarga
    for ad in $appdirs; do

    # Normalizar nombre: los Toolbox crean DUPLICADOS con sufijo "-2"
    # Para exportar usaremos el nombre limpio (android-studio en lugar de android-studio-2)
    base_orig=$(basename "$ad")
    # Quita posible sufijo "-N" (duplicado de Toolbox)
    base=$(printf '%s' "$base_orig" | sed -E 's/-[0-9]+$//')
    # Solo viaja una variante por app (la primera)
    case " $exportados " in *" $base "*) continue;; esac
    exportados="$exportados $base"
        # si es un paquete apt (p. ej. blender), que lo instale apt
        case " $pkgs " in
            *" $base "*) apt_tiene_repo "$base" && continue ;;
        esac
        # (a) ¿sigue su archivo original en el disco?
        arch=$(find "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio" "$HOME/.cache" \
            -maxdepth 3 \( -iname "*${base}*.tar.gz" -o -iname "*${base}*.tar.xz" \
            -o -iname "*${base}*.tar.bz2" -o -iname "*${base}*.tgz" \
            -o -iname "*${base}*.tar.zst" -o -iname "*${base}*.zip" \
            -o -iname "*${base}*.AppImage" \) 2>/dev/null | head -1)
        if [ -n "$arch" ] && [ -f "$arch" ]; then
            cp -f "$arch" "$ori/" 2>/dev/null || continue
            cont=$(contenedor_portatil "$ad")
            echo "ART|$base|$(basename "$arch")|$cont" >> "$ori/mapa.txt" 2>/dev/null
            continue
        fi
        # (b) ¿está su URL de descarga en el historial?
        u=$(url_archivo_de "$base")
        if [ -n "$u" ]; then
            [ -f "$tmp/paquetes/urls.txt" ] || : > "$tmp/paquetes/urls.txt"
            cont=$(contenedor_portatil "$ad")
            echo "URL|$base|$u|$cont" >> "$tmp/paquetes/urls.txt"
            continue
        fi
        # (c) sin archivo original ni URL en el historial. Ahora no se decide por
        # TAMAÑO sino por CONFIANZA, y no hay ningun tope: la pregunta es solo
        # "¿se sabe volver a tener exactamente esta app?".
        #
        # Antes se copiaba SIEMPRE, y eso convertía un respaldo del dock en
        # 12 GB: IntelliJ IDEA (4,3 GB), PyCharm (3,6 GB) y Android Studio
        # (3,5 GB) se copiaban byte a byte. Y antes de eso, al revés: si la
        # carpeta pasaba de 300 MB no se copiaba NADA y esas apps se perdían.
        # Las dos cosas estaban mal.
        #
        # Ahora:
        #   • Si se sabe de dónde sale (API de JetBrains, Toolbox, historial,
        #     app-update.yml, apt, snap, flatpak, AppImage) y la URL responde
        #     de verdad -> se apunta con su versión exacta y NO se copian los
        #     4 GB. Al importar se recupera la MISMA versión, byte a byte: no
        #     se pierde nada y el respaldo tarda segundos.
        #   • Si NO se sabe, o la URL no responde -> se copia la carpeta
        #     ENTERA, sin límite de tamaño. Aunque pese 4 GB. Perder una app es
        #     infinitamente peor que un respaldo grande, y comprimir con zstd
        #     hace que incluso 4 GB se copien en pocos segundos.
        local tam_mb=0
        if [ -d "$ad" ]; then
            tam_mb=$(( $(du -sm "$ad" 2>/dev/null | cut -f1) + 1 ))
        fi

        cont=$(contenedor_portatil "$ad")

        # Se le pregunta a la app de donde sale. Da igual que no sepamos nada
        # de ella: va mirando AppImage, API de JetBrains, Toolbox, historial,
        # sus propios metadatos, snap, flatpak, apt… hasta que algo encaja.
        _tr=$(detectar_reinstalacion "$ad" "$base")
        _tipo="${_tr%%|*}"; _resto="${_tr#*|}"
        _dato="${_resto%%|*}"
        _ver="${_resto#*|}"

        if reinstalacion_fiable "$_tipo" "$_dato"; then
            case "$_tipo" in
                art)
                    # Es un AppImage suelto: pesa poco y se copia tal cual.
                    if [ -f "$ad/$_dato" ]; then
                        cp -f "$ad/$_dato" "$ori/" 2>/dev/null && \
                            echo "ART|$base|$_dato|$cont" >> "$ori/mapa.txt" 2>/dev/null
                    fi
                    ;;
                deb)
                    # Se instaló con un .deb suyo. Ese .deb es la app, asi que
                    # tiene que viajar en el respaldo; si ya esta copiado en
                    # paquetes/debs (porque es un paquete sin repo) no se copia
                    # otra vez.
                    _ya="$tmp/paquetes/debs/$_dato"
                    if [ ! -f "$_ya" ]; then
                        mkdir -p "$ori" 2>/dev/null
                        cp -f "$_dato" "$ori/" 2>/dev/null
                    fi
                    if [ -f "$_ya" ] || [ -f "$ori/$_dato" ]; then
                        echo "REINSTALL|$base|deb|$_dato|$_ver|$tam_mb|$cont" >> "$ori/mapa.txt" 2>/dev/null
                        n_reinstall_export=$(( ${n_reinstall_export:-0} + 1 ))
                    else
                        # No se ha podido copiar el .deb: entonces la app se
                        # copia entera, que siempre funciona.
                        [ "$tam_mb" -gt "$LIMITE_AVISO_MB" ] && n_copiada_pesada=$(( ${n_copiada_pesada:-0} + 1 ))
                    fi
                    ;;
                *)
                    # REINSTALL|<app>|<tipo>|<dato>|<versión>|<MB>|<destino>
                    echo "REINSTALL|$base|$_tipo|$_dato|$_ver|$tam_mb|$cont" >> "$ori/mapa.txt" 2>/dev/null
                    n_reinstall_export=$(( ${n_reinstall_export:-0} + 1 ))
                    ;;
            esac
            continue
        fi

        # No se sabe recuperarla: se copia entera. No hay tope de tamaño, y si
        # ocupa mucho se avisa al final para que se note en el resumen.
        if [ "$tam_mb" -gt "$LIMITE_AVISO_MB" ]; then
            n_copiada_pesada=$(( ${n_copiada_pesada:-0} + 1 ))
            mb_copiada_pesada=$(( ${mb_copiada_pesada:-0} + tam_mb ))
        fi

        mkdir -p "$ori/apps"
        if [ ! -e "$ori/apps/$base" ]; then
            cp -a "$ad" "$ori/apps/$base" 2>/dev/null || continue
        fi
        echo "APP|$base|$ad" >> "$ori/mapa.txt"
    done

    # contadores globales para el resumen (se recalculan: las URLs de portátiles
    # se suman a las ya guardadas por el bloque de .deb)
    n_urls_export=$(sed -n '/^URL|/p' "$tmp/paquetes/urls.txt" 2>/dev/null | wc -l)
    n_artefactos_export=$(grep -cE '^(ART|APP)\|' "$ori/mapa.txt" 2>/dev/null || echo 0)
}

# ─────────────────────────────────────────────────────────────────────────────
# RESPALDO DE PLANK: asistente con progreso, cancelar y volver atrás
#
# ANTES: primero una lista de tres para decidir, luego una ventana VACÍA
# durante 10 minutos sin saber qué pasaba y sin poder pararla. Si te
# equivocabas de opción solo quedaba cerrar y empezar de cero.
#
# AHORA:
#   1) Pregunta de golpe: "¿Respaldo TODO?", que es lo normal.
#   2) Si dices que no, eliges entre las tres opciones, con "Volver" para
#      rectificar.
#   3) La copia va con BARRA DE PROGRESO y botón Cancelar de verdad.
#   4) Al acabar, el resumen trae "Volver atrás" para rehacerlo.
# ─────────────────────────────────────────────────────────────────────────────

# Qué listas de paquetes se guardan (f_navbar / f_manuales). El resto de
# banderas se declaran arriba y siempre valen "true".

plank_exportar() {
    local carpeta que eleccion todo

    while true; do
        # ── 1) La pregunta directa ─────────────────────────────────────────
        # Va PRIMERO y de frente: respaldar todo es lo que se quiere casi
        # siempre, así que no hay que leer una lista para llegar ahí.
        "${ZEN[@]}" --question --title="Respaldo" \
            --text="¿Quieres respaldar <b>TODO</b>?\n\nSe guardará la configuración del dock, todos tus lanzadores con\nsus .desktop e iconos, tus scripts, el autostart y las listas de\npaquetes para poder reinstalarlo todo en otro ordenador." \
            --ok-label="Sí, respaldar todo" \
            --cancel-label="No, elegir qué" \
            --extra-button="Cancelar" --width=650 --height=290 2>/dev/null
        eleccion=$?
        case "$eleccion" in
            0)   f_navbar=true  f_manuales=true ;;   # Sí, respaldar todo
            255) return 0 ;;                          # Cancelar
            *)   f_navbar=false f_manuales=false ;;   # No, elegir qué
        esac

        if [ "$eleccion" != "0" ] && [ "$eleccion" != "255" ]; then
            # ── 2) Las tres opciones, con "Volver" para rectificar ──────────
            que=$("${ZEN[@]}" --list --title="Respaldo" \
                --text="¿Qué quieres respaldar? Puedes volver atrás si te has equivocado." \
                --column="Opción" --column="Qué guarda" \
                "Todo" "Config, lanzadores, scripts, iconos + TODOS los paquetes manuales y los del navbar" \
                "Solo los paquetes" "Lo mismo pero solo la lista de TODOS los paquetes que instalaste a mano" \
                "Navbar + solo paquetes de navbar" "Lo mismo pero solo los paquetes de las apps ancladas al dock" \
                --extra-button="Volver" \
                --width=820 --height=380 2>/dev/null)
            [ -z "$que" ] && return 0
            case "$que" in
                "Todo")                                     f_navbar=true  f_manuales=true ;;
                "Solo los paquetes")                        f_navbar=false f_manuales=true ;;
                "Navbar + solo paquetes de navbar")         f_navbar=true  f_manuales=false ;;
                *) f_navbar=false f_manuales=false; continue ;;   # "Volver"
            esac
        fi

        # ── Carpeta destino. Se pregunta DESPUÉS de qué respaldar, para no
        #    tener que repetirla si hay que rectificar. ────────────────────
        carpeta=$("${ZEN[@]}" --file-selection --directory \
            --title="¿Dónde guardar el respaldo?" \
            --filename="$HOME/" 2>/dev/null)
        [ -z "$carpeta" ] && return 0

        # ── 3) La copia, con barra de progreso y botón de cancelar ─────────
        plank_exportar_barra "$carpeta" && return 0

        # Cancelada: preguntar en vez de salir a pelo (antes no había salida).
        if "${ZEN[@]}" --question --title="Respaldo cancelado" \
             --text="Se paró antes de terminar.\\n\\n¿Empezar de nuevo?" \
             --ok-label="Empezar de nuevo" --cancel-label="Salir" 2>/dev/null; then
            continue
        fi
        return 0
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# La barra. El trabajo pesado va en un subshell aparte: si fuera en el mismo
# proceso, la ventana se quedaría congelada sin poder moverse ni cerrarse
# (justo lo que pasaba antes).
#
# El subshell va escribiendo el porcentaje (0-100) en un FIFO y zenity lo lee y
# lo pinta. Si se pulsa Cancelar, se mata el subshell y se limpia todo.
# ─────────────────────────────────────────────────────────────────────────────
plank_exportar_barra() {
    local carpeta="$1"
    local destino="$carpeta/respaldo-$FECHA.tar.zst"
    local tmp fifo ctr worker rc resumen intentos=0

    tmp=$(mktemp -d) || return 1
    ctr=$(mktemp) || { rm -rf "$tmp"; return 1; }
    fifo=$(mktemp -u); mkfifo "$fifo" 2>/dev/null || { rm -rf "$tmp" "$ctr"; return 1; }

    ( plank_exportar_trabajo "$tmp" "$destino" "$fifo" "$ctr" ) &
    worker=$!

    "${ZEN[@]}" --progressbar --title="Respaldo" \
        --text="Guardando el respaldo… (pulsa Cancelar para parar)" \
        --percentage=0 --auto-close < "$fifo" 2>/dev/null
    rc=$?

    # rc 0 = llegó al 100%. Cualquier otra cosa = cancelado o ventana cerrada.
    if [ "$rc" -ne 0 ]; then
        kill -9 "$worker" 2>/dev/null
        while kill -0 "$worker" 2>/dev/null && [ "$intentos" -lt 25 ]; do
            sleep 0.2; intentos=$((intentos+1))
        done
        wait "$worker" 2>/dev/null
        rm -f "$fifo" "$ctr"; rm -rf "$tmp"
        return 1
    fi

    wait "$worker" 2>/dev/null
    rm -f "$fifo"

    if [ ! -f "$destino" ]; then
        rm -f "$ctr"; rm -rf "$tmp"
        "${ZEN[@]}" --error --title="Error" \
            --text="No se pudo guardar el respaldo." 2>/dev/null
        return 1
    fi

    # Los contadores los escribió el subshell (que es el que hizo el trabajo).
    n_navbar_export=0 n_manual_export=0 n_lanzadores_export=0
    n_apt_export=0 n_debs_export=0 n_urls_export=0 n_artefactos_export=0
    while IFS='=' read -r _clave _valor; do
        case "$_clave" in
            navbar)      n_navbar_export=$_valor ;;
            manuales)    n_manual_export=$_valor ;;
            lanzadores)  n_lanzadores_export=$_valor ;;
            apt)         n_apt_export=$_valor ;;
            debs)        n_debs_export=$_valor ;;
            urls)        n_urls_export=$_valor ;;
            artefactos)  n_artefactos_export=$_valor ;;
            reinstalables) n_reinstall_export=$_valor ;;
            recursos_grandes) n_recurso_grande=$_valor ;;
            copiadas_pesadas)  n_copiada_pesada=$_valor ;;
            mb_copiadas_pesadas) mb_copiada_pesada=$_valor ;;
        esac
    done < "$ctr"
    rm -f "$ctr"; rm -rf "$tmp"

    # ── 4) Resumen, con "Volver atrás" para rehacerlo ────────────────────────
    resumen="• Configuración de Plank y lanzadores"
    resumen+="\n• Apps personalizadas (Safari→Brave y otras)"
    resumen+="\n• Scripts (~/.local/bin)"
    resumen+="\n• Autostart"
    resumen+="\n• Iconos propios"
    [ "$n_lanzadores_export" -gt 0 ] && resumen+="\n• .desktop reales de $n_lanzadores_export lanzadores + recursos (portátil)"
    [ "$n_apt_export" -gt 0 ]       && resumen+="\n• $n_apt_export repositorios/claves apt (para reinstalar en otro PC)"
    [ "$n_navbar_export" -gt 0 ]    && resumen+="\n• Apps del navbar ($n_navbar_export paquetes)"
    [ "$n_debs_export" -gt 0 ]      && resumen+="\n• .deb locales de apps sin repo ($n_debs_export)"
    [ "$n_artefactos_export" -gt 0 ] && resumen+="\n• Apps portátiles con su fuente: $n_artefactos_export"
    [ "$n_reinstall_export" -gt 0 ] && resumen+="\n• $n_reinstall_export apps que NO se copiaron porque se sabe de dónde bajarlas (su origen y su versión exacta van guardados): al importar se recuperan solas"
    [ "${n_copiada_pesada:-0}" -gt 0 ] && resumen+="\n• $n_copiada_pesada apps SIN origen conocido, copiadas enteras aunque fueran enormes (${mb_copiada_pesada:-0} MB en total): mejor un respaldo grande que perder una app"
    [ "${n_recurso_grande:-0}" -gt 0 ] && resumen+="\n• $n_recurso_grande ejecutables gigantes no copiados porque su app ya se recupera de otra forma"
    [ "$n_urls_export" -gt 0 ]      && resumen+="\n• URLs para volver a bajar lo que no está en repos ($n_urls_export)"
    [ "$n_manual_export" -gt 0 ]    && resumen+="\n• Paquetes manuales ($n_manual_export)"
    local hay_instalador="no"
    if [ "$n_navbar_export" -gt 0 ] || [ "$n_manual_export" -gt 0 ]; then
        resumen+="\n• Script instalar.sh para reinstalar en otro PC"
        hay_instalador="sí (con instalar.sh)"
    fi

    "${ZEN[@]}" --info --title="Respaldo" \
        --extra-button="Volver atrás" \
        --text="Respaldo guardado en:\n<b>$destino</b>\n\nContiene:\n$resumen\n\nPaquetes para reinstalar: <b>$hay_instalador</b>" 2>/dev/null
    # 255 = le ha dado a "Volver atrás": rehacer el respaldo con otras opciones.
    [ "$?" = "255" ] && return 1
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# El trabajo pesado. Corre en segundo plano y va escribiendo el porcentaje en el
# FIFO. Los contadores del resumen se dejan en un fichero aparte porque, al ir
# en subshell, el proceso principal no los ve.
# ─────────────────────────────────────────────────────────────────────────────
plank_exportar_trabajo() {
    local tmp="$1" destino="$2" prog_fifo="$3" fich_ctr="$4"
    local log="${PLANK_BACKUP_LOG:-/dev/null}"
    local fase="inicio" t0
    t0=$(date +%s)
    # Al FIFO va SOLO el número: zenity no entiende otra cosa. El detalle de
    # qué fase tardó qué va a un log aparte (si hay PLANK_BACKUP_LOG puesto),
    # que es lo primero que hay que mirar si algún día vuelve a ir lento.
    prog() {
        local ahora; ahora=$(date +%s)
        echo "$1" >&3 2>/dev/null || true
        printf '%6ss  %s\n' "$((ahora-t0))" "$fase" >> "$log" 2>/dev/null || true
        fase="llega al $1%"; t0=$ahora
    }
    # La escritura del FIFO se abre UNA vez y se mantiene abierta todo el
    # trabajo. Si se abriera y cerrara en cada actualización, el lector vería
    # EOF entre progreso y progreso: zenity se cerraría y la siguiente
    # escritura se quedaría bloqueada para siempre esperando un lector.
    exec 3> "$prog_fifo" || return 1
    # Si zenity se cierra antes (el usuario cancela), escribir al FIFO da
    # SIGPIPE, que mataría el subshell. Se ignora y se sigue hasta que le
    # llegue el kill.
    trap '' PIPE
    trap 'exec 3>&-; apt_indice_limpiar; exit 143' TERM INT
    prog 2

    if $f_config && [ -d "$PLANK_CONFIG" ]; then
        mkdir -p "$tmp/config"
        cp -r "$PLANK_CONFIG"/. "$tmp/config/"
    fi
    if $f_config && [ -d "$PLANK_THEMES" ]; then
        mkdir -p "$tmp/themes"
        cp -r "$PLANK_THEMES"/. "$tmp/themes/"
    fi
    if $f_config && command -v dconf >/dev/null 2>&1; then
        dconf dump /net/launchpad/plank/ > "$tmp/plank.dconf" 2>/dev/null || true
    fi
    prog 8

    if $f_apps && [ -d "$APPS_DIR" ]; then
        mkdir -p "$tmp/applications"
        cp -r "$APPS_DIR"/. "$tmp/applications/"
    fi
    if $f_scripts && [ -d "$BIN_DIR" ]; then
        mkdir -p "$tmp/bin"
        cp -r "$BIN_DIR"/. "$tmp/bin/"
    fi
    if $f_autostart && [ -d "$AUTOSTART_DIR" ]; then
        mkdir -p "$tmp/autostart"
        cp -r "$AUTOSTART_DIR"/. "$tmp/autostart/"
    fi
    if $f_iconos && [ -d "$ICONS_CUSTOM" ]; then
        mkdir -p "$tmp/icons"
        cp -r "$ICONS_CUSTOM"/. "$tmp/icons/"
    fi
    prog 14

    # ── Lanzadores: guardar los .desktop reales y sus recursos ──
    # Para que al importar en cualquier PC los lanzadores funcionen IGUAL,
    # aunque el .desktop original haya cambiado de sitio o de contenido.
    salvar_recursos_lanzadores "$tmp"
    prog 30

    # ── Listas de paquetes (solo si se pidieron) ──
    n_navbar_export=0 n_manual_export=0 n_lanzadores_export=0 n_apt_export=0 n_debs_export=0 n_urls_export=0 n_artefactos_export=0 n_reinstall_export=0
    [ -f "$tmp/relaunchers/origen.txt" ] && n_lanzadores_export=$(grep -c "^DESKTOP|" "$tmp/relaunchers/origen.txt" 2>/dev/null || echo 0)
    if [ -e /var/lib/dpkg/status ] && { $f_navbar || $f_manuales; }; then
        mkdir -p "$tmp/paquetes"
        if $f_navbar; then
            paquetes_navbar > "$tmp/paquetes/navbar.txt" 2>/dev/null || true
            n_navbar_export=$(wc -l < "$tmp/paquetes/navbar.txt" 2>/dev/null || echo 0)
        fi
        if $f_manuales; then
            apt-mark showmanual 2>/dev/null | grep -v '^$' > "$tmp/paquetes/manuales.txt"
            n_manual_export=$(wc -l < "$tmp/paquetes/manuales.txt" 2>/dev/null || echo 0)
        fi
        prog 36

        # ── Repositorios y claves apt del sistema ──
        # Para poder reinstalar apps de PPAs/terceros (Brave, VS Code, Docker,
        # Unity Hub…) en un PC que no los tenga configurados. La URL del repo
        # viaja DENTRO de cada fuente: cada .list/.sources lleva su URI,
        # Suites, Components y Signed-By. Lo que faltaba era asegurar que la
        # CLAVE de firma también viajara, viva donde viva (/etc/apt/keyrings
        # o /usr/share/keyrings). Así, al importar se vuelve a montar cada
        # repositorio igual que estaba (URL + clave), sin depender de la red.
        local apt_tmp="$tmp/apt"
        mkdir -p "$apt_tmp/sources.list.d" "$apt_tmp/keyrings"
        if [ -d /etc/apt/sources.list.d ]; then
            for _f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$_f" ] || continue
                grep -qE '^\s*(deb|Types:\s*deb)' "$_f" 2>/dev/null || continue
                cp -f "$_f" "$apt_tmp/sources.list.d/" 2>/dev/null || true
            done
        fi
        # Claves: NO se copia la carpeta /etc/apt/keyrings entera. Se lee cada
        # fuente (que ya lleva la URL) y se guarda SOLO la clave que referencia:
        # por línea "Signed-By:" (formato .sources) o por "signed-by=" inline
        # en líneas deb (.list). Cada clave viaja con la ruta EXACTA que tenía,
        # para que al importar se coloque otra vez en su mismo sitio.
        local _f2 _sb _kb2
        : > "$apt_tmp/keyrings/origen.txt"
        for _f2 in "$apt_tmp"/sources.list.d/*.list "$apt_tmp"/sources.list.d/*.sources; do
            [ -f "$_f2" ] || continue
            _sb=$(grep -m1 '^[[:space:]]*Signed-By:' "$_f2" 2>/dev/null | sed 's/.*Signed-By:[[:space:]]*//' | tr -d ' \r')
            if [ -z "$_sb" ]; then
                _sb=$(grep -oE 'signed-by=[^[:space:]]+' "$_f2" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ']')
            fi
            [ -n "$_sb" ] || continue
            case "$_sb" in
                /*) [ -f "$_sb" ] || continue
                    _kb2=$(basename "$_sb")
                    if [ ! -f "$apt_tmp/keyrings/$_kb2" ]; then
                        cp -f "$_sb" "$apt_tmp/keyrings/$_kb2" 2>/dev/null || continue
                    fi
                    grep -q "|keyrings/$_kb2$" "$apt_tmp/keyrings/origen.txt" 2>/dev/null || \
                        echo "KEY|$_sb|keyrings/$_kb2" >> "$apt_tmp/keyrings/origen.txt" ;;
            esac
        done
        n_apt_export=$(( $(ls "$apt_tmp/sources.list.d" 2>/dev/null | wc -l) + $(sed -n '/^KEY|/p' "$apt_tmp/keyrings/origen.txt" 2>/dev/null | wc -l) ))

        # ── .deb locales para apps que NO están en ningún repo ──
        # docker-desktop, opencode, ulauncher… se instalaron con un .deb bajado
        # a mano y apt no puede reinstalarlos en otro PC (no tienen repo). Si su
        # .deb original sigue en el disco (Descargas, Documentos, Escritorio o la
        # caché del actualizador), viaja en el respaldo y al importar se
        # reinstala con apt ./… (que resuelve dependencias). Si el .deb ya no
        # existe, sus ejecutables siguen viajando por relaunchers/exec (portátil).
        n_debs_export=0
        prog 40

        # ── Índice de qué paquetes PUEDE instalar apt ────────────────────────
        # ANTES: por cada uno de los ~1900 paquetes se hacía un
        #   grep -rq "^Package: X$" sobre /var/lib/apt/lists (274 MB).
        #   1900 × 0,15 s ≈ 5 min, y el bucle se hacía DOS veces (este y el de
        #   las URLs) → casi 10 minutos de ventana en blanco para un respaldo.
        # AHORA: se lee el índice UNA vez (0,6 s), se guarda el conjunto
        #   ordenado de nombres disponibles y se calcula con comm cuáles NO
        #   están en ningún repo. Solo esos necesitan .deb local o URL, así que
        #   el trabajo se reduce a unos pocos.
        local idx="$tmp/paquetes/.idx"
        : > "$idx.consulta"; : > "$idx.disponibles"; : > "$idx.sin-repo"
        cat "$tmp/paquetes/navbar.txt" "$tmp/paquetes/manuales.txt" 2>/dev/null \
            | sed 's/:.*$//' | grep -v '^$' | grep -v ' ' | sort -u > "$idx.consulta"
        if [ -s "$idx.consulta" ]; then
            # Un único recorrido de los índices de apt, no uno por paquete.
            apt_indice_disponibles && cp -f "$APT_IDX_CACHE" "$idx.disponibles"
            [ -s "$idx.disponibles" ] || : > "$idx.disponibles"
            comm -23 "$idx.consulta" "$idx.disponibles" > "$idx.sin-repo"
        fi
        prog 52

        # Los .deb que hay en el disco, listados UNA vez. Antes se lanzaba un
        # find sobre Descargas/Documentos/Escritorio/caché POR CADA paquete.
        local debs_disco="$idx.debs"
        find "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio" "$HOME/.cache" \
            -maxdepth 3 -iname "*.deb" 2>/dev/null \
            | while IFS= read -r _f; do printf '%s|%s\n' "$(basename "$_f")" "$_f"; done \
            | sort -u > "$debs_disco"

        mkdir -p "$tmp/paquetes/debs"
        while IFS= read -r _p; do
            case "$_p" in ""|*\ *) continue;; esac
            # ¿tiene repo apt? no -> a ver si su .deb sigue en el disco. Si sí,
            # ya se reinstala solo de la URL/repo respaldada.
            # index() = coincidencia literal en el nombre, como el case de antes.
            _deb=$(awk -F'|' -v p="$_p" 'index($1, p) > 0 { print $2; exit }' "$debs_disco" 2>/dev/null)
            [ -n "$_deb" ] && [ -f "$_deb" ] && cp -f "$_deb" "$tmp/paquetes/debs/" 2>/dev/null || true
        done < "$idx.sin-repo"
        n_debs_export=$(ls "$tmp/paquetes/debs/" 2>/dev/null | wc -l)
        [ "$n_debs_export" -gt 0 ] || rm -rf "$tmp/paquetes/debs"
        prog 66

        # ── Si el .deb ya no está en el disco: guardar la URL de DONDE se
        #    descargó (historial de descargas de Firefox/Chrome, terminal o
        #    enlace estable conocido) para que instalar.sh lo vuelva a bajar
        #    en el otro PC. Así NO viaja la app entera: viaja solo el enlace.
        #    Solo se consulta para los paquetes sin repo (los de arriba): por
        #    eso la búsqueda en el historial no se hace 1900 veces.
        n_urls_export=0
        : > "$tmp/paquetes/urls.txt"
        while IFS= read -r _p; do
            case "$_p" in ""|*\ *) continue;; esac
            ls "$tmp/paquetes/debs/" 2>/dev/null | grep -qi "$_p" && continue
            _url=$(url_deb_de "$_p")
            [ -n "$_url" ] && echo "URL|$_p|$_url" >> "$tmp/paquetes/urls.txt"
        done < "$idx.sin-repo"
        n_urls_export=$(sed -n '/^URL|/p' "$tmp/paquetes/urls.txt" 2>/dev/null | wc -l)
        [ "$n_urls_export" -gt 0 ] || rm -f "$tmp/paquetes/urls.txt"
        # Los ficheros auxiliares NO deben viajar en el .tar.gz.
        rm -f "$idx.consulta" "$idx.disponibles" "$idx.sin-repo" "$debs_disco"
        prog 72

        # Script de instalación tolerante: solo instala lo que falta y existe
        cat > "$tmp/paquetes/instalar.sh" << 'PAQEOF'
#!/bin/bash
# Instala paquetes guardados en una copia de seguridad.
# Solo instala los que EXISTAN en los repositorios y NO estén ya instalados.
# Uso:
#   sudo bash instalar.sh                -> instala los manuales (manuales.txt)
#   sudo bash instalar.sh lista.txt      -> instala los de la lista indicada
#   sudo bash instalar.sh pkg1 pkg2 ...  -> instala esos paquetes concretos
[ "$(id -u)" -eq 0 ] || { echo "ERROR: hay que ejecutarlo con sudo."; exit 1; }
cd "$(dirname "$0")" || exit 1

# Hogar del PC de ORIGEN (guardado al exportar): sirve para traducir las
# rutas de apps portátiles al hogar de ESTE PC (sea cual sea el nombre de
# usuario, p. ej. /home/otro/... -> /home/nueva).
ORIGEN_HOME=""
[ -f ../relaunchers/origen.txt ] && ORIGEN_HOME=$(sed -n 's/^ORIGEN_HOME|//p' ../relaunchers/origen.txt 2>/dev/null | head -1)

# Hogar REAL del usuario en ESTE PC: al ejecutarse con sudo, $HOME apunta a
# /root; los apps portátiles deben volver al hogar del usuario (SUDO_USER).
DEST_HOME=""
if [ -n "$SUDO_USER" ]; then
    DEST_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
fi
[ -n "$DEST_HOME" ] || DEST_HOME="$HOME"
[ -n "$ORIGEN_HOME" ] || ORIGEN_HOME="$DEST_HOME"

# Restaurar repositorios y claves apt que venían en la copia (carpeta "apt"
# justo al lado de paquetes/: ../apt). Con cp -rn NO se pisa lo que el PC
# destino ya tenga configurado; solo se añade lo que le falta.
if [ -d ../apt/sources.list.d ]; then
    mkdir -p /etc/apt/sources.list.d
    cp -rn ../apt/sources.list.d/* /etc/apt/sources.list.d/ 2>/dev/null || true
fi
if [ -d ../apt/keyrings ]; then
    # Cada clave se devuelve a la ruta EXACTA que tenía en el PC de origen
    # (p. ej. /usr/share/keyrings/microsoft.gpg de VS Code), usando el mapa
    # keyrings/origen.txt que guardó el export: "KEY|/ruta/exacta|keyrings/nombre".
    if [ -f ../apt/keyrings/origen.txt ]; then
        while IFS='|' read -r _tipo _ruta _rel; do
            [ "$_tipo" = "KEY" ] || continue
            [ -n "$_ruta" ] || continue
            [ -f "../apt/keyrings/$_rel" ] || continue
            mkdir -p "$(dirname "$_ruta")"
            [ -e "$_ruta" ] || cp -f "../apt/keyrings/$_rel" "$_ruta" 2>/dev/null || true
        done < ../apt/keyrings/origen.txt
    fi
    # Cualquier clave sin ruta anotada acaba en el sitio habitual.
    mkdir -p /etc/apt/keyrings
    for _k in ../apt/keyrings/*.gpg ../apt/keyrings/*.asc; do
        [ -f "$_k" ] || continue
        cp -rn "$_k" /etc/apt/keyrings/ 2>/dev/null || true
    done
fi

echo "== Actualizando repositorios =="
apt-get update -qq
instalados=0; saltados=0; errores=0
instalar_uno() {
    local pkg="$1"
    [ -n "$pkg" ] || return
    pkg="${pkg%%:*}"
    case "$pkg" in *[[:space:]]*) return;; esac
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        saltados=$((saltados+1)); return
    fi
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        if apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1; then
            instalados=$((instalados+1))
        else
            errores=$((errores+1))
            echo "ERROR instalando: $pkg"
        fi
    else
        saltados=$((saltados+1))
    fi
}
if [ $# -eq 0 ]; then
    LISTA="manuales.txt"
    [ -s "$LISTA" ] || { echo "No hay lista de paquetes en la copia."; exit 0; }
    while IFS= read -r p; do instalar_uno "$p"; done < "$LISTA"
elif [ $# -eq 1 ] && [ -f "$1" ]; then
    while IFS= read -r p; do instalar_uno "$p"; done < "$1"
else
    for p in "$@"; do instalar_uno "$p"; done
fi

# Instalar los archivos .deb locales que venían en la copia (apps sin
# repositorio: docker-desktop, opencode…). Se usa apt ./para que resuelva
# dependencias, igual que al instalarlas a mano en su día.
if [ -d debs ] && ls debs/*.deb >/dev/null 2>&1; then
    echo "== Instalando archivos .deb del respaldo =="
    for _deb in debs/*.deb; do
        [ -f "$_deb" ] || continue
        if apt-get install -y "./$_deb" >/dev/null 2>&1; then
            instalados=$((instalados+1))
        else
            errores=$((errores+1))
            echo "ERROR instalando: $_deb"
        fi
    done
fi

# Apps portátiles (JetBrains Toolbox, HeidiSQL…): el export guardó su archivo
# original (tar.gz/AppImage/zip) en "origen/" o su URL. Aquí se extrae/copia
# en la misma carpeta donde vivía en el PC de origen (mapa.txt).
if [ -d origen ] && [ -s origen/mapa.txt ]; then
    echo "== Reconstruyendo apps portátiles del respaldo (origen/) =="
    while IFS='|' read -r _tipo _app _fich _cont _v5 _v6 _v7; do
        case "$_tipo" in
            ART)
        [ -f "origen/$_fich" ] || continue
        _fpath=$(readlink -f "origen/$_fich") || continue
        # traducir hogar de origen a este PC
        _cont="${_cont/#$ORIGEN_HOME/$DEST_HOME}"
        mkdir -p "$_cont" 2>/dev/null || continue
        echo "extrayendo $_fich  ->  $_cont/"
        case "$_fich" in
            *.tar.gz|*.tgz)  tar -xzf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.xz)        tar -xJf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.bz2)       tar -xjf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.zst)       tar --zstd -xf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.zip)           unzip -q -o "$_fpath" -d "$_cont" 2>/dev/null ;;
            *.AppImage)      chmod +x "$_fpath" 2>/dev/null; cp -f "$_fpath" "$_cont/" 2>/dev/null ;;
            *) continue ;;
        esac
                ;;
            APP)
        # app portátil pequeña que viaja con su carpeta entera (HeidiSQL…)
        _dest="${_fich/#$ORIGEN_HOME/$DEST_HOME}"
        [ -d "origen/apps/$_app" ] || continue
        mkdir -p "$dest" 2>/dev/null || continue
        cp -rn "origen/apps/$_app"/. "$_dest"/ 2>/dev/null || continue
                ;;
            REINSTALL)
        # App ENORME que en el respaldo no se copió (habría sido 4 GB). En su
        # lugar se guardó CÓMO volver a conseguirla, detectado dinámicamente:
        #   REINSTALL|<app>|<tipo>|<dato>|<versión>|<MB>|<carpeta destino>
        # tipo = url | apt | snap | flatpak | manual
        _tipo_app="$_fich"    # campo 3
        _dato="$_cont"        # campo 4
        _dest="$_v7"          # campo 7
        _dest="${_dest/#$ORIGEN_HOME/$DEST_HOME}"

        case "$_tipo_app" in
            deb)
                # La app se instalaba con un .deb suyo, y ese .deb viaja en el
                # respaldo. Se instala desde aqui con apt, que ademas arrastra
                # las dependencias que necesite.
                _deb=""
                [ -f "$_dato" ] && _deb="$_dato"
                [ -z "$_deb" ] && [ -f "$_cont" ] && _deb="$_cont"
                [ -z "$_deb" ] && [ -f "$ORIGEN/paquetes/debs/$_dato" ] && _deb="$ORIGEN/paquetes/debs/$_dato"
                [ -z "$_deb" ] && [ -f "$ORIGEN/$_dato" ] && _deb="$ORIGEN/$_dato"
                if [ -n "$_deb" ]; then
                    echo "instalando $_app (su .deb: $(basename "$_deb"))"
                    if apt-get install -y "$_deb" >/dev/null 2>&1; then
                        instalados=$((instalados+1))
                    else
                        errores=$((errores+1))
                        echo "ERROR instalando $(basename "$_deb") de $_app"
                    fi
                else
                    echo "AVISO: el .deb de $_app no esta en el respaldo."
                    echo "       Bajalo de nuevo e instalalo a mano; el resto del"
                    echo "       respaldo (dock, lanzadores, scripts, paquetes) es valido."
                    errores=$((errores+1))
                fi
                ;;
            apt)
                echo "instalando $_app (paquete apt: $_dato)"
                if apt-get install -y --no-install-recommends "$_dato" >/dev/null 2>&1; then
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1))
                    echo "ERROR instalando el paquete $_dato de $_app"
                fi
                ;;
            snap)
                echo "instalando $_app (snap: $_dato)"
                if command -v snap >/dev/null 2>&1 && snap install "$_dato" >/dev/null 2>&1; then
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1))
                    echo "ERROR instalando el snap $_dato de $_app"
                fi
                ;;
            flatpak)
                echo "instalando $_app (flatpak: $_dato)"
                if command -v flatpak >/dev/null 2>&1 \
                   && flatpak install -y "$_dato" >/dev/null 2>&1; then
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1))
                    echo "ERROR instalando el flatpak $_dato de $_app"
                fi
                ;;
            url)
                # Se vuelve a bajar el archivo original y se deja en la misma
                # carpeta donde vivía en el PC de origen. El tipo se saca de la
                # PROPIA extensión, sin suponer que todo es un .tar.gz: puede
                # ser un .tar.xz, un .zip, un AppImage o un instalador.
                _archivo=$(printf '%s' "$_dato" | sed 's/[?#].*$//;s|.*/||')
                case "$_archivo" in
                    ""|*/*) _archivo="$_app.tar.gz" ;;
                esac
                echo "bajando $_app  ->  $_dest/"
                mkdir -p "$_dest" 2>/dev/null || continue
                _bajado=1
                if command -v wget >/dev/null 2>&1; then
                    wget -q -O "$_archivo" "$_dato" || _bajado=0
                elif command -v curl >/dev/null 2>&1; then
                    curl -fsSL -o "$_archivo" "$_dato" || _bajado=0
                else
                    errores=$((errores+1))
                    echo "ERROR: ni wget ni curl para bajar $_app"
                    continue
                fi
                if [ "$_bajado" = "0" ]; then
                    rm -f "$_archivo" 2>/dev/null
                    errores=$((errores+1))
                    echo "ERROR bajando $_app desde $_dato"
                    continue
                fi
                case "$_archivo" in
                    *.tar.gz|*.tgz)  tar -xzf "$_archivo" -C "$_dest" 2>/dev/null ;;
                    *.tar.xz)        tar -xJf "$_archivo" -C "$_dest" 2>/dev/null ;;
                    *.tar.bz2)       tar -xjf "$_archivo" -C "$_dest" 2>/dev/null ;;
                    *.tar.zst)       tar --zstd -xf "$_archivo" -C "$_dest" 2>/dev/null ;;
                    *.zip)           unzip -qo "$_archivo" -d "$_dest" 2>/dev/null ;;
                    *.deb|*.rpm)     (cd "$_dest" && apt-get install -y "./$_archivo") >/dev/null 2>&1
                                    if [ $? -ne 0 ]; then
                                        errores=$((errores+1))
                                        echo "ERROR instalando $_archivo de $_app"
                                    fi ;;
                    *.AppImage)      cp -f "$_archivo" "$_dest/" 2>/dev/null
                                    chmod +x "$_dest/$_archivo" 2>/dev/null ;;
                    # Sin extension no se ve que es: casi siempre es un tar.gz.
                    *)               tar -xzf "$_archivo" -C "$_dest" 2>/dev/null ;;
                esac
                rm -f "$_archivo" 2>/dev/null
                instalados=$((instalados+1))
                ;;
            gh)
                # La app decía de qué GitHub sale (en sus propios metadatos),
                # así que se le pregunta a GitHub qué archivo publica para
                # Linux y se baja ese. Sin tablas de nombres: el owner/repo lo
                # escribió la propia app.
                echo "buscando $_app en GitHub ($_dato)"
                _gh_url=$(curl -fsSL --max-time 20 \
                    "https://api.github.com/repos/${_dato}/releases/latest" 2>/dev/null \
                    | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' \
                    | cut -d'"' -f4 \
                    | grep -iE 'linux|appimage|\.deb$|\.tar\.gz$|\.rpm$' | head -1)
                if [ -z "$_gh_url" ]; then
                    echo "AVISO: GitHub no publica ningun archivo de Linux para $_dato."
                    echo "       Bajalo a mano de https://github.com/$_dato/releases"
                    continue
                fi
                echo "bajando $_app  ->  $_dest/"
                mkdir -p "$_dest" 2>/dev/null || continue
                _archivo=$(printf '%s' "$_gh_url" | sed 's/[?#].*$//;s|.*/||')
                if command -v wget >/dev/null 2>&1; then
                    wget -q -O "$_archivo" "$_gh_url" || { rm -f "$_archivo"; continue; }
                elif command -v curl >/dev/null 2>&1; then
                    curl -fsSL -o "$_archivo" "$_gh_url" || { rm -f "$_archivo"; continue; }
                else
                    continue
                fi
                case "$_archivo" in
                    *.tar.gz|*.tgz)  tar -xzf "$_archivo" -C "$_dest" 2>/dev/null ;;
                    *.zip)           unzip -qo "$_archivo" -d "$_dest" 2>/dev/null ;;
                    *.deb)           (cd "$_dest" && apt-get install -y "./$_archivo") >/dev/null 2>&1 ;;
                    *)               chmod +x "$_archivo" 2>/dev/null ;;
                esac
                [ "${_archivo##*.}" = "AppImage" ] && chmod +x "$_archivo" 2>/dev/null
                rm -f "$_archivo" 2>/dev/null
                instalados=$((instalados+1))
                ;;
            *)
                # No se pudo detectar de donde sale. Se avisa con claridad en
                # vez de fallar en silencio: el resto del respaldo (dock,
                # lanzadores, scripts, paquetes) sigue siendo válido.
                echo "AVISO: no se pudo saber como reinstalar $_app (era $_v5 MB)."
                echo "       Buscala en su web y listo; el resto del respaldo es valido."
                ;;
        esac
                ;;
            *) continue ;;
        esac
        instalados=$((instalados+1))
    done < origen/mapa.txt
fi

# Apps cuyo .deb original ya no estaba en el disco de origen: instalar.sh
# vuelve a bajarlo DESDE DONDE SE DESCARGÓ (la URL viaja en urls.txt).
# Así no hace falta que la app entera viaje: solo el enlace.
if [ -s urls.txt ]; then
    echo "== Bajando .deb/tar.gz desde su origen (urls.txt) =="
    while IFS='|' read -r _tipo _p _u _tgt; do
        [ "$_tipo" = "URL" ] || continue
        _nom="${_u%%\?*}"; _nom=$(basename "$_nom")
        [ -n "$_nom" ] || continue
        echo "bajando $_p  ->  $_u"
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$_nom" "$_u" 2>/dev/null || { errores=$((errores+1)); echo "ERROR bajando: $_u"; continue; }
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$_nom" "$_u" 2>/dev/null || { errores=$((errores+1)); echo "ERROR bajando: $_u"; continue; }
        else
            errores=$((errores+1)); echo "ERROR: ni wget ni curl para $_p"; continue
        fi
        # .deb -> se instala con apt (resuelve dependencias); comprimidos ->
        # se extraen en la carpeta que ocupaban en el PC de origen (campo 4).
        case "$_nom" in
            *.deb)
                if apt-get install -y "./$_nom" >/dev/null 2>&1; then
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1)); echo "ERROR instalando: $_nom"
                fi ;;
            *)
                if [ -n "$_tgt" ]; then
                    _tgt="${_tgt/#$ORIGEN_HOME/$DEST_HOME}"
                    mkdir -p "$_tgt" 2>/dev/null || { errores=$((errores+1)); echo "ERROR destino: $_tgt"; continue; }
                    echo "extrayendo $_nom  ->  $_tgt/"
                    case "$_nom" in
                        *.tar.gz|*.tgz)  tar -xzf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.xz)        tar -xJf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.bz2)       tar -xjf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.zst)       tar --zstd -xf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.zip)           unzip -q -o "$_nom" -d "$_tgt" 2>/dev/null ;;
                        *.AppImage)      chmod +x "$_nom" 2>/dev/null; cp -f "$_nom" "$_tgt/" 2>/dev/null ;;
                        *) continue ;;
                    esac
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1)); echo "ERROR: sin destino para $_nom"
                fi ;;
        esac
    done < urls.txt
fi

echo
echo "== Resumen =="
echo "Instalados: $instalados"
echo "Ya estaban o no disponibles (saltados): $saltados"
echo "Errores: $errores"
PAQEOF
        chmod +x "$tmp/paquetes/instalar.sh"
    fi

    prog 88

    # ── Artefactos de origen de apps portátiles (según lo que haya) ──
    # Después de conocer los lanzadores: para cada app portátil bajo
    # ~/Aplicaciones u otros contenedores, guarda su archivo original (tar.gz,
    # AppImage…) si sigue en el disco, o su URL de descarga si no. instalar.sh
    # decide al importar: extrae el archivo o baja la URL.
    salvar_artefactos_origen "$tmp"
    prog 92

    # Los contadores van a un fichero aparte, NO dentro de la copia: no tienen
    # que acabar en el .tar.gz.
    {
        echo "navbar=$n_navbar_export"
        echo "manuales=$n_manual_export"
        echo "lanzadores=$n_lanzadores_export"
        echo "apt=$n_apt_export"
        echo "debs=$n_debs_export"
        echo "urls=$n_urls_export"
        echo "artefactos=$n_artefactos_export"
        echo "reinstalables=$n_reinstall_export"
        echo "recursos_grandes=${n_recurso_grande:-0}"
        echo "copiadas_pesadas=${n_copiada_pesada:-0}"
        echo "mb_copiadas_pesadas=${mb_copiada_pesada:-0}"
    } > "$fich_ctr" 2>/dev/null || true

    prog 96

    # El tar final es lo más lento de todo (comprime todo lo juntado), por eso
    # se deja el último trozo de barra para él.
    #
    # Se comprime con ZSTD y no con gzip a propósito: gzip va a ~30 MB/s y solo
    # lo que se copia son binarios ya comprimidos (un .tar de una app entera
    # pesa 4 GB y con zstd tarda la mitad de lo que con gzip, con el mismo
    # resultado). Con apps grandes copiadas enteras la diferencia es de minutos.
    if ! tar --zstd -cf "$destino" -C "$tmp" . 2>/dev/null; then
        # Por si este tar no supiera zstd: se reintenta con gzip.
        tar -czf "$destino" -C "$tmp" . 2>/dev/null || {
            rm -f "$destino" 2>/dev/null
            prog 0
            exit 1
        }
    fi
    rm -rf "$tmp"
    apt_indice_limpiar
    prog 100
    exec 3>&-
    return 0
}

plank_importar() {
    local raiz
    local candidatos=()
    for raiz in "$HOME" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio"; do
        [ -d "$raiz" ] || continue
        while IFS= read -r f; do
            candidatos+=("$f")
        done < <(find "$raiz" -maxdepth 1 -type f \( -name "respaldo-*.tar.zst" -o -name "respaldo-*.tar.gz" -o -name "respaldo-plank*.tar.zst" -o -name "respaldo-plank*.tar.gz" -o -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" \) 2>/dev/null)
    done
    IFS=$'\n' candidatos=($(printf "%s\n" "${candidatos[@]}" | sort -u))

    local origen
    origen=$("${ZEN[@]}" --list --title="Copias de seguridad encontradas" \
        --text="Se han detectado automáticamente estas copias. Elige una:" \
        --column="Archivo" "Buscar en otra carpeta..." "${candidatos[@]}" \
        --width=720 --height=380 2>/dev/null)
    [ -z "$origen" ] && return

    if [ "$origen" = "Buscar en otra carpeta..." ]; then
        local carpeta
        carpeta=$("${ZEN[@]}" --file-selection --directory \
            --title="Elegir carpeta donde están las copias de seguridad" \
            --filename="$HOME/" 2>/dev/null)
        [ -z "$carpeta" ] && return
        mapfile -t candidatos < <(find "$carpeta" -maxdepth 1 -type f \( -name "respaldo-*.tar.zst" -o -name "respaldo-*.tar.gz" -o -name "respaldo-plank*.tar.zst" -o -name "respaldo-plank*.tar.gz" -o -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" -o -name "*.tar.gz" -o -name "*.tar.zst" \) 2>/dev/null | sort)
        if [ "${#candidatos[@]}" -eq 0 ]; then
            "${ZEN[@]}" --warning --title="Sin copias de seguridad" \
                --text="No se encontraron copias (.tar.gz) en:\\n$carpeta" 2>/dev/null
            return
        fi
        origen=$("${ZEN[@]}" --list --title="Copias de seguridad encontradas" \
            --text="Selecciona la copia a restaurar:" \
            --column="Archivo" "${candidatos[@]}" \
            --width=640 --height=360 2>/dev/null)
        [ -z "$origen" ] && return
    fi

    if ! tar -tzf "$origen" >/dev/null 2>&1; then
        "${ZEN[@]}" --error --title="Error" \
            --text="El archivo seleccionado no es una copia válida." 2>/dev/null
        return
    fi

    local modo
    modo=$("${ZEN[@]}" --list --title="Cómo restaurar" \
        --text="¿Cómo quieres aplicar la copia de seguridad?" \
        --column="Opción" --column="Descripción" \
        "Mezclar" "Dejar lo que ya tiene el panel y añadir lo que falte de la copia" \
        "Reemplazar" "Borrar la configuración actual y restaurar solo lo de la copia" \
        --width=680 --height=320 2>/dev/null)
    [ -z "$modo" ] && return

    if [ "$modo" = "Reemplazar" ]; then
        if ! "${ZEN[@]}" --question --title="Reemplazar configuración" \
            --text="Se borrará la configuración actual de Plank y sus lanzadores.\\n\\nSe hará una copia de seguridad de lo actual antes.\\n¿Continuar?" 2>/dev/null; then
            return
        fi
    fi

    # Parar Plank ANTES de tocar nada: Plank se lanza desde el propio dock,
    # así que si sigue corriendo, al terminar escribe su dock-items (el orden
    # viejo) en dconf y pisa el orden restaurado. Se vuelve a lanzar al final.
    if pgrep -x plank >/dev/null 2>&1; then
        pkill -x plank 2>/dev/null || true
        sleep 1
    fi

    # Copia de seguridad de la configuración actual
    [ -d "$PLANK_CONFIG" ] && cp -r "$PLANK_CONFIG" "$PLANK_CONFIG.bak-$FECHA" 2>/dev/null || true

    local tmp
    tmp=$(mktemp -d)
    case "$origen" in
        *.tar.zst)              tar --zstd -xf "$origen" -C "$tmp" 2>/dev/null ;;
        *.tar.gz|*.tgz)         tar -xzf "$origen" -C "$tmp" 2>/dev/null ;;
        *.tar.xz)               tar -xJf "$origen" -C "$tmp" 2>/dev/null ;;
        *)                      tar -xf "$origen" -C "$tmp" 2>/dev/null ;;
    esac

    if [ "$modo" = "Reemplazar" ]; then
        if [ -d "$tmp/config" ]; then
            rm -rf "$PLANK_CONFIG"
            mkdir -p "$HOME/.config"
            cp -r "$tmp/config" "$PLANK_CONFIG"
        fi
        if [ -d "$tmp/themes" ]; then
            rm -rf "$PLANK_THEMES"
            mkdir -p "$HOME/.local/share/plank"
            cp -r "$tmp/themes" "$PLANK_THEMES"
        fi
        if [ -f "$tmp/plank.dconf" ] && command -v dconf >/dev/null 2>&1; then
            dconf load /net/launchpad/plank/ < "$tmp/plank.dconf" 2>/dev/null || true
        fi
    else
        # MEZCLAR: conservar lo actual y añadir solo lo que falte
        mkdir -p "$PLANK_CONFIG/dock1/launchers"
        if [ -d "$tmp/config/dock1/launchers" ]; then
            for dock in "$tmp"/config/dock1/launchers/*.dockitem; do
                [ -f "$dock" ] || continue
                local base; base=$(basename "$dock")
                local destino_dock="$PLANK_CONFIG/dock1/launchers/$base"
                if [ ! -f "$destino_dock" ]; then
                    cp "$dock" "$destino_dock"
                fi
            done
        fi
        if [ -d "$tmp/themes" ]; then
            mkdir -p "$PLANK_THEMES"
            for tema in "$tmp"/themes/*/; do
                [ -d "$tema" ] || continue
                local nombre_tema; nombre_tema=$(basename "$tema")
                [ -d "$PLANK_THEMES/$nombre_tema" ] || cp -r "$tema" "$PLANK_THEMES/$nombre_tema"
            done
        fi
    fi

    # ── Apps personalizadas (Safari→Brave y otras) ──
    if [ -d "$tmp/applications" ]; then
        mkdir -p "$APPS_DIR"
        for f in "$tmp"/applications/*; do
            [ -e "$f" ] || continue
            local basef; basef=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$APPS_DIR/$basef" ]; then
                cp -r "$f" "$APPS_DIR/$basef"
            fi
        done
    fi
    if [ -d "$tmp/bin" ]; then
        mkdir -p "$BIN_DIR"
        for f in "$tmp"/bin/*; do
            [ -e "$f" ] || continue
            local baseb; baseb=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$BIN_DIR/$baseb" ]; then
                cp -r "$f" "$BIN_DIR/$baseb"
                chmod +x "$BIN_DIR/$baseb" 2>/dev/null || true
            fi
        done
    fi
    if [ -d "$tmp/autostart" ]; then
        mkdir -p "$AUTOSTART_DIR"
        for f in "$tmp"/autostart/*; do
            [ -e "$f" ] || continue
            local basea; basea=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$AUTOSTART_DIR/$basea" ]; then
                cp -r "$f" "$AUTOSTART_DIR/$basea"
            fi
        done
    fi
    if [ -d "$tmp/icons" ]; then
        mkdir -p "$ICONS_CUSTOM"
        cp -r "$tmp"/icons/. "$ICONS_CUSTOM/"
    fi

    # ── Corregir rutas de usuario (para que funcione en otro PC) ──
    # Los .desktop y lanzadores guardan /home/USUARIO_ORIGEN/... → /home/$USER
    if [ -d "$PLANK_CONFIG/dock1/launchers" ]; then
        sed -i "s|/home/[^/]*/|/home/$USER/|g" "$PLANK_CONFIG"/dock1/launchers/*.dockitem 2>/dev/null || true
    fi
    if [ -d "$APPS_DIR" ]; then
        # En los .desktop se corrigen Exec, Icon y Path
        find "$APPS_DIR" -maxdepth 1 -name "*.desktop" -exec \
            sed -i "s|/home/[^/]*/|/home/$USER/|g" {} + 2>/dev/null || true
    fi
    if [ -d "$AUTOSTART_DIR" ]; then
        find "$AUTOSTART_DIR" -maxdepth 1 -name "*.desktop" -exec \
            sed -i "s|/home/[^/]*/|/home/$USER/|g" {} + 2>/dev/null || true
    fi

    # ── Restaurar los .desktop reales de los lanzadores y reescribir los
    #    .dockitem que apunten a rutas que no existen en este PC ──
    restaurar_recursos_lanzadores "$tmp"

    # ── Asegurar el orden de los lanzadores en dconf (dock-items): se usa el
    #    orden que venía guardado en el respaldo (relaunchers/orden.txt) para
    #    que el dock quede igual que en el PC de origen; los lanzadores nuevos
    #    (modo Mezclar) se añaden al final ──
    if [ -f "$tmp/relaunchers/orden.txt" ]; then
        orden_dock_asegurar "$tmp/relaunchers/orden.txt"
    else
        orden_dock_asegurar
    fi

    # ── Reinstalar paquetes incluidos en la copia (tú eliges) ──
    if [ -f "$tmp/paquetes/instalar.sh" ]; then
        local opciones_paq=()
        [ -s "$tmp/paquetes/navbar.txt" ]   && opciones_paq+=("Apps del navbar/dock ($(wc -l < "$tmp/paquetes/navbar.txt"))")
        [ -s "$tmp/paquetes/manuales.txt" ] && opciones_paq+=("Paquetes instalados manualmente ($(wc -l < "$tmp/paquetes/manuales.txt"))")

        local eleccion
        if [ "${#opciones_paq[@]}" -gt 0 ]; then
            eleccion=$("${ZEN[@]}" --list --title="Reinstalar paquetes" \
                --text="La copia incluye paquetes instalados.\\nSelecciona qué reinstalar (puedes marcar varios con Ctrl+clic):" \
                --column="Elegir" --width=680 --height=340 --multiple \
                "${opciones_paq[@]}" 2>/dev/null)
        else
            eleccion=""
        fi

        if [ -n "$eleccion" ]; then
            local lista_sel="$tmp/paquetes/seleccion.txt"
            : > "$lista_sel"
            while IFS= read -r op; do
                case "$op" in
                    "Apps del navbar/dock"*) cat "$tmp/paquetes/navbar.txt" >> "$lista_sel" ;;
                    "Paquetes instalados manualmente"*) cat "$tmp/paquetes/manuales.txt" >> "$lista_sel" ;;
                esac
            done <<< "$eleccion"
            sort -u "$lista_sel" -o "$lista_sel"

            if [ -s "$lista_sel" ]; then
                local pass
                pass=$("${ZEN[@]}" --password --title="Contraseña de administrador" \
                    --text="Introduce tu contraseña para instalar los <b>$(wc -l < "$lista_sel")</b> paquetes seleccionados:" 2>/dev/null)
                if [ -n "$pass" ]; then
                    (
                        echo "$pass" | sudo -S bash "$tmp/paquetes/instalar.sh" "$lista_sel" > /tmp/plank-paquetes.log 2>&1
                        echo "100"
                    ) | "${ZEN[@]}" --progress --pulsate --auto-close \
                        --title="Instalando paquetes" \
                        --text="Instalando los paquetes seleccionados...\\nEsto puede tardar unos minutos." 2>/dev/null
                    resumen=$(tail -n 5 /tmp/plank-paquetes.log 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                    "${ZEN[@]}" --info --title="Paquetes" \
                        --text="Listo. Se instaló lo que faltaba (saltando lo que ya estaba o no existe).\\n\\n<b>Resumen:</b>\\n$resumen\\n\\nLog completo en /tmp/plank-paquetes.log" 2>/dev/null
                fi
            else
                "${ZEN[@]}" --info --title="Paquetes" \
                    --text="No hay paquetes instalables en la copia. Se restauró la configuración de Plank igualmente." 2>/dev/null
            fi
        fi
    fi

    rm -rf "$tmp"

    plank_reiniciar

    "${ZEN[@]}" --info --title="Importar copia de Plank" \
        --text="Copia <b>$( [ "$modo" = "Mezclar" ] && echo "mezclada" || echo "restaurada" )</b> correctamente.\\nPlank se ha reiniciado.\\n\\nConfiguración anterior guardada en:\\n$PLANK_CONFIG.bak-$FECHA" 2>/dev/null
}

plank_eliminar() {
    local raiz
    local candidatos=()
    for raiz in "$HOME" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio"; do
        [ -d "$raiz" ] || continue
        while IFS= read -r f; do
            candidatos+=("$f")
        done < <(find "$raiz" -maxdepth 1 -type f \( -name "respaldo-*.tar.zst" -o -name "respaldo-*.tar.gz" -o -name "respaldo-plank*.tar.zst" -o -name "respaldo-plank*.tar.gz" -o -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" \) 2>/dev/null)
    done
    IFS=$'\n' candidatos=($(printf "%s\n" "${candidatos[@]}" | sort -u))

    if [ "${#candidatos[@]}" -eq 0 ]; then
        "${ZEN[@]}" --warning --title="Sin copias de seguridad" \
            --text="No se encontraron copias (.tar.gz) en tu home, Descargas, Documentos o Escritorio." 2>/dev/null
        return
    fi

    local elegida
    elegida=$("${ZEN[@]}" --list --title="Eliminar copia de seguridad" \
        --text="Selecciona la copia que quieres eliminar:" \
        --column="Archivo" "${candidatos[@]}" \
        --width=720 --height=380 2>/dev/null)
    [ -z "$elegida" ] && return

    if ! "${ZEN[@]}" --question --title="Confirmar eliminación" \
        --text="Se eliminará para siempre:\\n<b>$elegida</b>\\n\\n¿Continuar?" 2>/dev/null; then
        return
    fi

    if rm -f "$elegida"; then
        "${ZEN[@]}" --info --title="Eliminar copia de seguridad" \
            --text="Copia eliminada:\\n$elegida" 2>/dev/null
    else
        "${ZEN[@]}" --error --title="Error" --text="No se pudo eliminar:\\n$elegida" 2>/dev/null
    fi
}

# Si el script se ejecuta directamente (no se “sourcea” para pruebas),
# se muestra el menú principal; si se importa como librería no pasa nada.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Al abrir el menu se comprueba que el propio "Respaldo" este anclado en el
    # dock con su icono. Si ya esta bien, no se toca nada (y el dock no
    # parpadea); si falta o esta desactualizado, se pone y se recarga Plank.
    plank_asegurar_lanzador

    ACCION=$("${ZEN[@]}" --list --title="Respaldo" \
        --text="¿Qué quieres hacer con la configuración de Plank?" \
        --column="Acción" --column="Descripción" \
        "Respaldar" "Guardar un respaldo (te pregunta si quieres todo)" \
        "Restaurar" "Volver a poner un respaldo guardado" \
        "Borrar respaldo" "Borrar un respaldo guardado" \
        --extra-button="Salir" \
        --width=680 --height=380 2>/dev/null)

    case "$ACCION" in
        Respaldar) plank_exportar ;;
        Restaurar) plank_importar ;;
        "Borrar respaldo") plank_eliminar ;;
        *) exit 0 ;;
    esac
fi