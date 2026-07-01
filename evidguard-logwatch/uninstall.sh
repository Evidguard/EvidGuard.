#!/bin/bash
# EvidGuard LogWatch v5 — uninstall.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Ejecutar como root: sudo ./uninstall.sh"
    exit 1
fi

echo "[INFO] Deteniendo servicios..."
for unit in evidguard-monitor.path evidguard-monitor.service; do
    systemctl stop    "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
done

echo "[INFO] Eliminando archivos del sistema..."
rm -f /etc/systemd/system/evidguard-monitor.path
rm -f /etc/systemd/system/evidguard-monitor.service
rm -f /usr/local/bin/evidguard-report
rm -rf /opt/evidguard-logwatch

systemctl daemon-reload
echo "[OK] Servicios y binarios eliminados."

echo ""
read -rp "¿Eliminar también logs y datos de estado? [s/N]: " resp
if [[ "${resp:-}" =~ ^[Ss]$ ]]; then
    rm -rf /var/lib/evidguard
    rm -rf /var/log/evidguard
    echo "[OK] Datos y logs eliminados."
else
    echo "[INFO] Datos preservados en /var/lib/evidguard y /var/log/evidguard"
fi

echo ""
read -rp "¿Eliminar /etc/msmtprc (contiene tu App Password de Gmail)? [s/N]: " resp2
if [[ "${resp2:-}" =~ ^[Ss]$ ]]; then
    rm -f /etc/msmtprc
    echo "[OK] /etc/msmtprc eliminado."
else
    echo "[INFO] /etc/msmtprc conservado. Contiene credenciales — elimínalo manualmente si ya no lo necesitas."
fi

echo ""
echo "[OK] Desinstalación completada."
