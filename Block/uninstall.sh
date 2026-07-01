#!/bin/bash
# uninstall.sh — Desinstalador de EVG Write-Blocker

set -e
[ "$(id -u)" = "0" ] || { echo "Requiere root: sudo ./uninstall.sh"; exit 1; }

echo "Desinstalando EVG Write-Blocker..."

systemctl stop evg-blockdev.service 2>/dev/null || true
systemctl disable evg-blockdev.service 2>/dev/null || true

rm -f /etc/systemd/system/evg-blockdev.service
rm -f /etc/udev/rules.d/80-evg-blockdev.rules
rm -f /usr/local/sbin/evg-setro
rm -f /usr/local/sbin/evg-log
rm -f /usr/local/sbin/evg-blockall
rm -f /usr/local/bin/evg-unblock
rm -f /usr/local/bin/evg-unblock-gui
rm -f /usr/share/applications/evg-unblock.desktop
rm -f /etc/logrotate.d/evg-blockdev
rm -rf /var/lib/evg-unblock

# Eliminar iconos del escritorio
find /home/*/Desktop -name "evg-unblock.desktop" -delete 2>/dev/null || true

systemctl daemon-reload
udevadm control --reload-rules

echo "✓ evg Write-Blocker desinstalado."
echo "  El log se mantiene en /var/log/evg-blockdev.log"
echo "  Los dispositivos siguen en su estado actual hasta reiniciar."
