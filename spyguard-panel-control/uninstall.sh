#!/bin/bash
# SpyGuard Control Panel - Desinstalador
set -e

APP_NAME="spyguard-cp"
INSTALL_DIR="/opt/spyguard-cp"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
PIXMAPS_DIR="/usr/share/pixmaps"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== SpyGuard Control Panel - Desinstalador ===${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Ejecuta con sudo o como root${NC}"
    exit 1
fi

read -p "¿Eliminar SpyGuard Control Panel? [s/N]: " confirm
if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo "Cancelado."
    exit 0
fi

echo -e "${YELLOW}Eliminando archivos...${NC}"
rm -rf "$INSTALL_DIR"
rm -f "$BIN_DIR/$APP_NAME"
rm -f "$DESKTOP_DIR/$APP_NAME.desktop"
rm -f "$PIXMAPS_DIR/$APP_NAME.png"

for user_dir in /home/*/Desktop; do
    [ -d "$user_dir" ] && rm -f "$user_dir/$APP_NAME.desktop"
done

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Desinstalación completa${NC}"
