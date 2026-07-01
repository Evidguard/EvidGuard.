#!/bin/bash
# ============================================================
# install.sh — Instalador de EVG Write-Blocker para RPi
# Instala todos los componentes del sistema forense:
#   - Regla udev
#   - Scripts de sistema
#   - GUI (evg-unblock)
#   - Servicio systemd
#   - Acceso directo de escritorio
# ============================================================

set -e

# --- Colores ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }
hdr()  { echo -e "\n${CYAN}══ $1 ══${NC}"; }

# --- Verificaciones previas ---
if [ "$(id -u)" != "0" ]; then
    err "Ejecuta el instalador como root: sudo ./install.sh"
    exit 1
fi

if ! uname -r | grep -q "rpi\|raspi\|arm" 2>/dev/null; then
    warn "No se detecta Raspberry Pi. Continuando de todas formas..."
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    EvidGuard Write-Blocker — Instalador          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# --- Dependencias ---
hdr "Verificando dependencias"

PKGS_NEEDED=()

if ! command -v blockdev &>/dev/null; then
    PKGS_NEEDED+=("util-linux")
fi

if ! python3 -c "import tkinter" &>/dev/null 2>&1; then
    PKGS_NEEDED+=("python3-tk")
fi

if ! python3 -c "from PIL import Image" &>/dev/null 2>&1; then
    PKGS_NEEDED+=("python3-pil")
fi

if ! command -v udevadm &>/dev/null; then
    PKGS_NEEDED+=("udev")
fi

if [ ${#PKGS_NEEDED[@]} -gt 0 ]; then
    info "Instalando paquetes: ${PKGS_NEEDED[*]}"
    apt-get update -qq
    apt-get install -y "${PKGS_NEEDED[@]}"
    ok "Dependencias instaladas"
else
    ok "Todas las dependencias están presentes"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Scripts de sistema ---
hdr "Instalando scripts de sistema"

install -m 755 "$SCRIPT_DIR/scripts/evg-setro"  /usr/local/sbin/evg-setro
ok "evg-setro → /usr/local/sbin/"

install -m 755 "$SCRIPT_DIR/scripts/evg-log"    /usr/local/sbin/evg-log
ok "evg-log → /usr/local/sbin/"

install -m 755 "$SCRIPT_DIR/scripts/evg-blockall" /usr/local/sbin/evg-blockall
ok "evg-blockall → /usr/local/sbin/"

# --- GUI ---
hdr "Instalando interfaz gráfica"

install -m 755 "$SCRIPT_DIR/gui/evg-unblock" /usr/local/bin/evg-unblock
ok "evg-unblock → /usr/local/bin/"

# --- Imágenes (logo e icono) ---
hdr "Instalando imágenes"

mkdir -p /usr/share/evg/img
if [ -f "$SCRIPT_DIR/img/logo.png" ]; then
    install -m 644 "$SCRIPT_DIR/img/logo.png" /usr/share/evg/img/logo.png
    ok "logo.png → /usr/share/evg/img/"
fi
if [ -f "$SCRIPT_DIR/img/icono.png" ]; then
    install -m 644 "$SCRIPT_DIR/img/icono.png" /usr/share/evg/img/icono.png
    install -m 644 "$SCRIPT_DIR/img/icono.png" /usr/share/pixmaps/evg-unblock.png
    ok "icono.png → /usr/share/evg/img/ y /usr/share/pixmaps/"
fi

# Wrapper con sudo automático para lanzar desde el escritorio
cat > /usr/local/bin/evg-unblock-gui << 'WRAPPER'
#!/bin/bash
# Lanzador de EVG UnBlock con privilegios
# Captura variables de entorno gráfico ANTES de elevar (Debian 13 / polkit)
ENV_PAIRS=()
for VAR in DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_RUNTIME_DIR \
           DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE GDK_BACKEND; do
    VAL="${!VAR}"
    [ -n "$VAL" ] && ENV_PAIRS+=("$VAR=$VAL")
done
[ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && ENV_PAIRS+=("DISPLAY=:0")

if [ "$(id -u)" != "0" ]; then
    if command -v pkexec &>/dev/null; then
        pkexec env "${ENV_PAIRS[@]}" /usr/local/bin/evg-unblock
    else
        sudo env "${ENV_PAIRS[@]}" /usr/local/bin/evg-unblock
    fi
else
    /usr/local/bin/evg-unblock
fi
WRAPPER
chmod 755 /usr/local/bin/evg-unblock-gui
ok "evg-unblock-gui (lanzador) → /usr/local/bin/"

# --- Regla udev ---
hdr "Instalando regla udev"

install -m 644 "$SCRIPT_DIR/udev/80-evg-blockdev.rules" \
    /etc/udev/rules.d/80-evg-blockdev.rules
ok "Regla udev → /etc/udev/rules.d/80-evg-blockdev.rules"

udevadm control --reload-rules
ok "Reglas udev recargadas"

# --- Servicio systemd ---
hdr "Instalando servicio systemd"

install -m 644 "$SCRIPT_DIR/systemd/evg-blockdev.service" \
    /etc/systemd/system/evg-blockdev.service
ok "Servicio → /etc/systemd/system/evg-blockdev.service"

systemctl daemon-reload
systemctl enable evg-blockdev.service
ok "Servicio habilitado en el arranque"

# --- Fichero de log ---
hdr "Configurando logs"
touch /var/log/evg-blockdev.log
chmod 644 /var/log/evg-blockdev.log
ok "Log → /var/log/evg-blockdev.log"

# --- Directorio de estado persistente ---
hdr "Configurando estado persistente"
mkdir -p /var/lib/evg-unblock
chmod 755 /var/lib/evg-unblock
# Si no existe aún el fichero de estado, crearlo vacío
if [ ! -f /var/lib/evg-unblock/state.json ]; then
    echo "{}" > /var/lib/evg-unblock/state.json
    chmod 644 /var/lib/evg-unblock/state.json
fi
ok "Estado persistente → /var/lib/evg-unblock/state.json"

# Logrotate
cat > /etc/logrotate.d/evg-blockdev << 'LOGROTATE'
/var/log/evg-blockdev.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE
ok "Logrotate configurado"

# --- Acceso directo en el escritorio ---
hdr "Creando acceso directo en el escritorio"

DESKTOP_FILE="/usr/share/applications/evg-unblock.desktop"
cat > "$DESKTOP_FILE" << 'DESKTOP'
[Desktop Entry]
Name=EVG UnBlock
Name[es]=EVG UnBlock
Comment=Gestor forense de escritura en dispositivos de bloque
Comment[es]=Herramienta de write-blocking forense al estilo EVG
Exec=/usr/local/bin/evg-unblock-gui
Icon=evg-unblock
Terminal=false
Type=Application
Categories=System;Security;
Keywords=forense;forensic;blockdev;write-blocker;EVG;
StartupNotify=true
DESKTOP
chmod 644 "$DESKTOP_FILE"
ok "Acceso directo → $DESKTOP_FILE"

# Copiar al escritorio si existe
for home_dir in /home/*; do
    desktop_dir="$home_dir/Desktop"
    if [ -d "$desktop_dir" ]; then
        cp "$DESKTOP_FILE" "$desktop_dir/evg-unblock.desktop"
        chown "$(stat -c '%u:%g' "$home_dir")" "$desktop_dir/evg-unblock.desktop"
        ok "Icono copiado a $desktop_dir"
    fi
done

# --- Aplicar bloqueo inmediato ---
hdr "Aplicando bloqueo inicial"
/usr/local/sbin/evg-blockall
ok "Dispositivos actuales bloqueados en READ-ONLY"

# --- Resumen ---
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Instalación completada con éxito         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Comandos disponibles:${NC}"
echo -e "    ${YELLOW}sudo evg-unblock${NC}          → Interfaz gráfica"
echo -e "    ${YELLOW}sudo evg-blockall${NC}         → Bloquear todos los discos"
echo -e "    ${YELLOW}sudo blockdev --setro /dev/sda${NC} → Bloquear disco manual"
echo -e "    ${YELLOW}sudo blockdev --setrw /dev/sda${NC} → Desbloquear disco"
echo -e "    ${YELLOW}cat /var/log/evg-blockdev.log${NC} → Ver registro"
echo ""
echo -e "  ${CYAN}El sistema bloqueará automáticamente cualquier dispositivo${NC}"
echo -e "  ${CYAN}que se conecte (udev) y en cada arranque (systemd).${NC}"
echo ""
warn "Reinicia para confirmar el servicio de arranque: sudo reboot"
echo ""
