#!/bin/bash
# SpyGuard Control Panel - Instalador v2.2.1
set -e

APP_NAME="spyguard-cp"
INSTALL_DIR="/opt/spyguard-cp"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
PIXMAPS_DIR="/usr/share/pixmaps"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== SpyGuard Control Panel - Instalador v2.2.1 ===${NC}"

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Ejecuta con sudo o como root${NC}"
    echo -e "Ejemplo: ${YELLOW}sudo ./install.sh${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER" 2>/dev/null || echo "")

# Verificar dependencias
echo -e "${YELLOW}[1/6] Verificando dependencias...${NC}"
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error: python3 no está instalado${NC}"
    exit 1
fi

if ! python3 -c "import tkinter" 2>/dev/null; then
    echo -e "${YELLOW}Instalando python3-tk...${NC}"
    apt-get update -qq && apt-get install -y -qq python3-tk || {
        echo -e "${RED}No se pudo instalar python3-tk. Instálalo manualmente:${NC}"
        echo -e "${YELLOW}sudo apt install python3-tk${NC}"
        exit 1
    }
fi

# Verificar archivos fuente
echo -e "${YELLOW}[2/6] Verificando archivos fuente...${NC}"
for f in lib/spyguard_control_panel.py bin/spyguard-cp; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
        echo -e "${RED}Error: Falta archivo fuente: $f${NC}"
        exit 1
    fi
done

# Crear directorios
echo -e "${YELLOW}[3/6] Creando directorios de instalación...${NC}"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,lib,assets}
mkdir -p "$DESKTOP_DIR" "$PIXMAPS_DIR"

# Copiar archivos
echo -e "${YELLOW}[4/6] Copiando archivos...${NC}"
cp "$SCRIPT_DIR/lib/spyguard_control_panel.py" "$INSTALL_DIR/lib/"
cp "$SCRIPT_DIR/bin/spyguard-cp" "$INSTALL_DIR/bin/"
chmod 755 "$INSTALL_DIR/bin/spyguard-cp"
chmod 644 "$INSTALL_DIR/lib/spyguard_control_panel.py"

if [ -f "$SCRIPT_DIR/assets/logo.png" ]; then
    cp "$SCRIPT_DIR/assets/logo.png" "$INSTALL_DIR/assets/"
fi
if [ -f "$SCRIPT_DIR/assets/icon.png" ]; then
    cp "$SCRIPT_DIR/assets/icon.png" "$INSTALL_DIR/assets/"
    cp "$SCRIPT_DIR/assets/icon.png" "$PIXMAPS_DIR/$APP_NAME.png"
fi

# Symlink global
echo -e "${YELLOW}[5/6] Creando ejecutable global...${NC}"
ln -sf "$INSTALL_DIR/bin/spyguard-cp" "$BIN_DIR/$APP_NAME"
chmod 755 "$BIN_DIR/$APP_NAME"

# .desktop del sistema
echo -e "${YELLOW}[6/6] Instalando lanzador .desktop...${NC}"
cat > "$DESKTOP_DIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=SpyGuard Control Panel
Comment=Panel de control para servicios SpyGuard
Exec=$BIN_DIR/$APP_NAME
Icon=$APP_NAME
Type=Application
Terminal=false
Categories=System;Security;Monitor;
Keywords=spyguard;security;systemd;monitor;
StartupNotify=true
EOF
chmod 644 "$DESKTOP_DIR/$APP_NAME.desktop"

# Copiar al Desktop del usuario que ejecutó sudo
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] && [ -d "$REAL_HOME/Desktop" ]; then
    cp "$DESKTOP_DIR/$APP_NAME.desktop" "$REAL_HOME/Desktop/"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/$APP_NAME.desktop"
    chmod 755 "$REAL_HOME/Desktop/$APP_NAME.desktop"
    echo -e "${GREEN}  → Lanzador copiado al Desktop de $REAL_USER${NC}"
else
    echo -e "${YELLOW}  → No se detectó Desktop de usuario. Copia manualmente:${NC}"
    echo -e "     cp $DESKTOP_DIR/$APP_NAME.desktop ~/Desktop/"
fi

# Actualizar cachés
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ Instalación completa${NC}"
echo -e "${GREEN}  Ejecutable global: $BIN_DIR/$APP_NAME${NC}"
echo -e "${GREEN}  Instalación:       $INSTALL_DIR${NC}"
echo -e "${GREEN}  Lanzador menú:    $DESKTOP_DIR/$APP_NAME.desktop${NC}"
echo ""
echo -e "${YELLOW}Cómo usar:${NC}"
echo -e "  • Doble clic en el icono del Desktop"
echo -e "  • Menú de aplicaciones → SpyGuard Control Panel"
echo -e "  • Terminal: ${YELLOW}spyguard-cp${NC}"
echo ""
echo -e "${YELLOW}Desinstalar:${NC} sudo $INSTALL_DIR/uninstall.sh"
