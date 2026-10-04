#!/usr/bin/env python3
"""
arreglar-panel-xml.py — deja el xfce4-panel.xml del tirón y bien formado.

POR QUE EXISTE
Antes esto se hacia con unaopensource de "sed" dentro de panel.sh. Esos sed
tenian dos fallos que rompian el panel:

  1. Buscaban textos tipo  value="notification-plugin"/>  SIN espacio antes del
     "/>", pero el XML se escribe con espacio:  value="notification-plugin" />.
     Osea que no(find)ban nada, sin dar ningun error. Por eso la bandeja de
     sistema (donde sale el icono del wifi) nunca se creaba.

  2. Al activar those sed (arreglando el punto 1) insertaban etiquetas sin
     cerrar. xfconf entonces decia:
       "Error en la linea 131: el documento termina inesperadamente con
        elementos todavia abiertos"
     y el panel, al no poder leer su config, arrancaba con la de POR DEFECTO:
     solo se veia el menu de aplicaciones y nada mas.

Aqui no hay ni un sed. Se usa xml.etree, que siempre devuelve un documento
correctamente cerrado, y al final se comprueba con ET.parse que el resultado
sigue siendo XML valido.

QUE DEJA EL PANEL (de izquierda a derecha)
  [manzana] [appmenu] | separador que expande |
  ... area de estado a la DERECHA: bateria, bandeja (wifi), volumen, ...
  ... lanzadores, fecha y hora

USO:  arreglo-panel-xml.py ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
"""

import sys
import xml.etree.ElementTree as ET

# Iconos que se dejan FUERA de la bandeja. El objetivo es que en la bandeja se
# vea solo el wifi, que es lo que pediste: el resto (actualizaciones de Mint,
#Blueman, portapapeles, llavero...) solo llena la barra de ruido.
OCULTOS_BANDEJA = [
    "mintupdate.py",
    "tray.py",
    "applet.py",
    "blueman-tray",
    "blueman-applet",
    "blueman applet",
    "Blueman Applet",
    "clipman",
    "seahorse",
    "gnome-keyring",
    "keyring",
]


def prop(nombre, tipo, valor, hijos=()):
    p = ET.Element("property", name=nombre, type=tipo)
    if valor is not None:
        p.set("value", valor)
    for h in hijos:
        p.append(h)
    return p


def valor(nodo, nombre, por_defecto=None):
    # OJO: iter() y no findall(). Los plugins (plugin-1, plugin-2...) NO son
    # hijos directos del <channel>: estan dentro de <property name="plugins">.
    # Con findall() no se encontraba ninguno y la parte de los separadores se
    # quedaba sin hacer, en silencio.
    for h in nodo.iter("property"):
        if h.get("name") == nombre:
            return h.get("value")
    return por_defecto


def fijar_valor(nodo, nombre, tipo, nuevo):
    """Pone una propiedad dentro de nodo. Si ya existe, la cambia; si no, la anade."""
    for h in nodo.findall("property"):
        if h.get("name") == nombre:
            h.set("type", tipo)
            h.set("value", nuevo)
            for sobrante in list(h.findall("property")):
                h.remove(sobrante)
            return h
    nuevo_h = ET.Element("property", name=nombre, type=tipo, value=nuevo)
    nodo.insert(0, nuevo_h)
    return nuevo_h


def construir_systray():
    """Devuelve el <property> del plugin systray con la lista de ocultos."""
    hijos = [
        prop("name-visible", "bool", "false"),
        prop("square-icons", "bool", "false"),
        prop("icon-size", "int", "0"),
    ]
    for nombre in ("hidden-items", "hidden-legacy-items"):
        array = ET.Element("property", name=nombre, type="array")
        for icono in OCULTOS_BANDEJA:
            v = ET.SubElement(array, "value")
            v.set("type", "string")
            v.set("value", icono)
        hijos.append(array)
    return prop("plugin-10", "string", "systray", hijos)


def main(path):
    tree = ET.parse(path)
    root = tree.getroot()

    print("XFCE4 PANEL")
    changed = []

    # ── 1) el menu global "appmenu" ──────────────────────────────────────────
    # Este es el que pone la barra de menus de la aplicacion abierta
    # (Archivo / Editar / Ver / Ayuda), el equivalente al menu de la manzanita.
    #
    # EL NOMBRE QUE FUNCIONA ES "appmenu", no "appmenu-xfce". No es que el
    # plugin este roto: viene del paquete xfce4-appmenu-plugin y su fichero es
    # libappmenu-xfce.so, pero el panel no busca el plugin por el nombre del
    # .so sino por el nombre del fichero .desktop, y ese se llama appmenu.desktop
    # (/usr/share/xfce4/panel/plugins/appmenu.desktop, que dice
    # X-XFCE-Module=appmenu-xfce). Con "appmenu-xfce" en el config el panel no
    # encuentra ningun .desktop y avisa:
    #     Plugin "appmenu-xfce-2" was not found and has been removed...
    # y lo borra, que es por lo que no salia la barra de menus.
    #
    # Ademas es un plugin EXTERNO (el .desktop no lleva X-XFCE-Internal=TRUE),
    # asi que no lo carga el panel en su propio proceso: lo lanza como hijo con
    #   panel/wrapper-2.0 libappmenu-xfce.so 2 <id> appmenu ...
    # Por eso tampoco aparece en /proc/<pid del panel>/maps, hay que mirarlo en
    # los procesos hijos. Lo mismo con systray, volumen y bateria.
    plugins_node = root.find("property[@name='plugins']")
    if plugins_node is None:
        print("ERROR: el XML no tiene <property name=\"plugins\">")
        return 1

    # plugin-2 tiene que ser SIEMPRE "appmenu", con sus tres propiedades.
    appmenu = None
    for hijo in list(plugins_node):
        if hijo.get("name") == "plugin-2":
            appmenu = hijo
            break
    if appmenu is None:
        appmenu = ET.SubElement(plugins_node, "property", name="plugin-2")
    valor_antes = appmenu.get("value")
    appmenu.set("type", "string")
    appmenu.set("value", "appmenu")
    for sobrante in list(appmenu.findall("property")):
        appmenu.remove(sobrante)
    dentro = prop("plugins", "empty", None, (prop("plugin-2", "empty", None, (
        prop("compact-mode", "bool", "false"),
        prop("bold-application-name", "bool", "true"),
        prop("expand", "bool", "true"),
    )),))
    appmenu.append(dentro)
    changed.append(
        "menu global de appmenu puesto en plugin-2"
        if valor_antes != "appmenu"
        else "menu global de appmenu correcto en plugin-2"
    )

    # y su id tiene que estar en plugin-ids, justo detras del menu de
    # aplicaciones (plugin-1), para que salga pegado a la manzana.
    for paneles in [p for p in root.findall("property") if p.get("name") == "panels"]:
        for panel in paneles.findall("property"):
            for h in panel.findall("property"):
                if h.get("name") == "plugin-ids":
                    ids = [v.get("value") for v in h]
                    if "2" not in ids:
                        ids.insert(ids.index("1") + 1 if "1" in ids else 0, "2")
                        for v in list(h):
                            h.remove(v)
                        for i in ids:
                            ET.SubElement(h, "value", type="int", value=i)
                        changed.append("plugin-2 (appmenu) añadido al panel")

    # ── 2) la bandeja de sistema (plugin-10) ──────────────────────────────────
    # Sin esto no hay donde dibujar los iconos: nm-applet puede estar corriendo
    # pero sin bandeja donde mostrarse, o sea invisible. De ahi que no saliese
    # el wifi.
    for p in list(root.iter("property")):
        if p.get("name") == "plugin-10":
            idx = None
            for parent in root.iter():
                for i, hijo in enumerate(list(parent)):
                    if hijo is p:
                        idx, padre = i, parent
                        break
                if idx is not None:
                    break
            if idx is not None:
                padre.remove(p)
                padre.insert(idx, construir_systray())
                changed.append("bandeja de sistema (systray) creada en plugin-10")

    # ── 3) separadores: el que empuja y el del final ──────────────────────────
    # El separador con expand=true es el que manda todo lo de la derecha (la
    # "barra de estado") al extremo derecho. Si no, la barra de estado se queda
    # pegada al menu.
    paneles = [p for p in root.findall("property") if p.get("name") == "panels"]
    if paneles:
        panel = None
        for h in paneles[0].findall("property"):
            if (h.get("name") or "").startswith("panel-"):
                panel = h
                break
        if panel is not None:
            ids = []
            for h in panel.findall("property"):
                if h.get("name") == "plugin-ids":
                    ids = [v.get("value") for v in h]
            separadores = [
                "plugin-%s" % i
                for i in ids
                if valor(root, "plugin-%s" % i) == "separator"
            ]
            if separadores:
                # El primero que se declare: que expanda (empuja la derecha).
                fijar_valor(
                    _plugin(root, separadores[0]), "expand", "bool", "true"
                )
                changed.append(
                    "separador %s: expand=true (la barra de estado va a la derecha)"
                    % separadores[0]
                )
                # El ultimo: que NO expanda, para que no se coma el hueco.
                if len(separadores) > 1:
                    fijar_valor(
                        _plugin(root, separadores[-1]), "expand", "bool", "false"
                    )
                    changed.append(
                        "separador %s: expand=false (ultimo, no se estira)"
                        % separadores[-1]
                    )

    # ── 4) ids que panel.sh dejaba colgando ───────────────────────────────────
    for paneles in [p for p in root.findall("property") if p.get("name") == "panels"]:
        for panel in paneles.findall("property"):
            for h in panel.findall("property"):
                if h.get("name") == "plugin-ids":
                    for v in list(h):
                        if v.get("value") in ("19", "21"):
                            h.remove(v)
                            changed.append("id de plugin suelto %s fuera" % v.get("value"))

    # ── 5) "expand" con type="empty" no vale: hay que ponerlo a bool ──────────
    # Asi lo leia xfconf y el separador no empujaba nada.
    for p in root.iter("property"):
        if p.get("name") == "expand" and p.get("type") in (None, "empty"):
            p.set("type", "bool")
            p.set("value", "false")
            changed.append("expand con type=empty pasado a bool")

    # ── 6) comprobacion: si esto falla, NO se escribe nada ────────────────────
    # OJO: sin xml_declaration=True aqui, porque esa opcion ya escribe la
    # declaracion y luego se escribia otra a mano: dos declaraciones seguidas y
    # el XML quedaba invalido ("XML or text declaration not at start").
    salida = ET.tostring(root, encoding="unicode")
    try:
        ET.fromstring(salida)
    except ET.ParseError as exc:
        print("ERROR: el XML reparado sigue sin ser valido: %s" % exc)
        return 1

    with open(path, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(salida)

    if changed:
        for c in dict.fromkeys(changed):
            print("  - %s" % c)
    else:
        print("  (no habia nada que arreglar)")
    return 0


def _plugin(root, nombre):
    for p in root.iter("property"):
        if p.get("name") == nombre:
            return p
    return ET.Element("property")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: %s <fichero xfce4-panel.xml>" % sys.argv[0])
        sys.exit(2)
    sys.exit(main(sys.argv[1]))