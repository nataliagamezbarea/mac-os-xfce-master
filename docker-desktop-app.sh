#!/usr/bin/env bash
# ============================================================
#  Docker Desktop · lanzador para Plank (mac-os-xfce)
#  Abrir  → motor encendido + ventana visible (o la levanta)
#  Cerrar → cuando la interfaz se cierre, el motor se apaga
# ------------------------------------------------------------
#  Fix "se cierra y se vuelve a abrir":
#   • El unit del sistema ya NO está acoplado a
#     graphical-session.target (ver ~/.config/systemd/user/
#     docker-desktop.service), por lo que apagar Docker ya no
#     tumba la sesión gráfica ni se re-arranca solo.
#   • Además, tras un cierre manual se deja una marca de tiempo:
#     si algo relanza este lanzador dentro de los siguientes
#     segundos (relanzamientos automáticos), se ignora y la
#     ventana NO vuelve a abrirse sola.
# ============================================================
set -u

BIN="/opt/docker-desktop/bin/docker-desktop"
LOCK="$HOME/.config/plank/docker-desktop.lock"
CLOSED="$HOME/.config/plank/docker-desktop.closed"
GUARD_SEG=25

# Proceso PRINCIPAL de la interfaz (excluye hijos --type=...)
gui_main() {
    ps -eo args \
        | grep -E '^/opt/docker-desktop/Docker Desktop( |$)' \
        | grep -v -- '--type='
}

# PIDs del backend real (puede vivir fuera de systemd)
backend_pids() {
    ps -eo pid,args \
        | grep -F '/opt/docker-desktop/bin/com.docker.backend' \
        | grep -v '[g]rep' \
        | awk '{print $1}'
}

kill_backend() {
    local pids
    pids=$(backend_pids)
    [ -n "$pids" ] && kill $pids 2>/dev/null
    sleep 1
    pids=$(backend_pids)
    [ -n "$pids" ] && kill -9 $pids 2>/dev/null
}

# ── 0) Guard anti-reapertura ──
#     Si se cerró hace menos de GUARD_SEG segundos, un relanzamiento
#     automático del lanzador NO debe volver a abrir la ventana.
if [ -f "$CLOSED" ]; then
    edad=$(( $(date +%s) - $(cat "$CLOSED" 2>/dev/null || echo 0) ))
    if [ "$edad" -lt "$GUARD_SEG" ]; then
        exit 0
    fi
    rm -f "$CLOSED"
fi

# ── A) ¿YA HAY INTERFAZ? → levantarla y salir ──
if gui_main | grep -q .; then
    # pedir la ventana del dashboard
    nohup "$BIN" >/dev/null 2>&1 &
    sleep 3
    command -v wmctrl >/dev/null 2>&1 && wmctrl -a "Docker" >/dev/null 2>&1 || true
    exit 0
fi

# ── B) Sin interfaz: si otro lanzador ya está abriendo, no estorbar ──
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    nohup "$BIN" >/dev/null 2>&1 &
    exit 0
fi

# ── C) Arranque limpio: matar backend huérfano, luego abrir ──
rm -f "$CLOSED"
kill_backend
sleep 2
nohup "$BIN" >/dev/null 2>&1 &
sleep 5

echo $$ > "$LOCK"
trap 'rm -f "$LOCK" 2>/dev/null' EXIT

# ── D) Esperar a que la interfaz se cierre de verdad ──
while gui_main | grep -q .; do
    sleep 2
done

# ── E) Apagar el motor (con gracia; si sigue, a la fuerza) ──
sleep 5
systemctl --user stop docker-desktop 2>/dev/null
kill_backend
date +%s > "$CLOSED"
exit 0
