#!/bin/bash
# EvidGuard LogWatch v6 — install.sh
# Compatible: Ubuntu 20.04+, Debian 11+, Raspberry Pi OS. Requiere root.
set -uo pipefail

APP="evidguard-logwatch"
INSTALL_DIR="/opt/${APP}"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Ejecutar como root: sudo ./install.sh"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          EvidGuard LogWatch v6 — Instalador                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ── Leer config ────────────────────────────────────────────────────────────────
if [[ ! -f "config/config.conf" ]]; then
    echo "[ERROR] No se encuentra config/config.conf"
    exit 1
fi
source config/config.conf

# ── Validar que el usuario ha editado la config ────────────────────────────────
if grep -qE 'TU_EMAIL|TU_APP_PASSWORD' config/config.conf; then
    echo "[ERROR] Edita config/config.conf con tu email antes de instalar."
    echo "        nano config/config.conf"
    exit 1
fi

# ── Detectar ruta del log de rclone manager ────────────────────────────────────
echo "[INFO] Detectando ruta del log de rclone manager..."
LOG_DETECTADO=""

if [[ "${RCLONE_GUI_LOG:-AUTO}" != "AUTO" ]]; then
    LOG_DETECTADO="$RCLONE_GUI_LOG"
    echo "[INFO] Ruta manual: $LOG_DETECTADO"
else
    if [[ -d "/root/.cache/com.rclone.manager" ]]; then
        LOG_DETECTADO="/root/.cache/com.rclone.manager/logs/rclone/main_engine.log"
        echo "[INFO] Detectado: rclone manager en /root"
    else
        for homedir in /home/*/; do
            if [[ -d "${homedir}.cache/com.rclone.manager" ]]; then
                LOG_DETECTADO="${homedir}.cache/com.rclone.manager/logs/rclone/main_engine.log"
                echo "[INFO] Detectado: rclone manager en ${homedir}"
                break
            fi
        done
    fi
fi

if [[ -z "$LOG_DETECTADO" ]]; then
    echo "  ⚠️  rclone manager no ha corrido aún en este sistema."
    LOG_DETECTADO="/root/.cache/com.rclone.manager/logs/rclone/main_engine.log"
    echo "     Ruta por defecto: $LOG_DETECTADO"
    echo "     El monitor arrancará en cuanto rclone manager cree su log."
fi

if [[ ! -f "$LOG_DETECTADO" ]]; then
    echo "  ⚠️  El log aún no existe. Haz una copia con rclone manager para crearlo."
fi

echo ""

# ── Dependencias ───────────────────────────────────────────────────────────────
echo "[INFO] Instalando dependencias..."
apt-get update -qq
apt-get install -y -qq msmtp msmtp-mta 2>/dev/null || true

# ── Directorios y ficheros de estado ──────────────────────────────────────────
echo "[INFO] Creando directorios y ficheros de estado..."

mkdir -p /var/log/evidguard
chmod 750 /var/log/evidguard

mkdir -p /var/lib/evidguard
chmod 750 /var/lib/evidguard

mkdir -p "$INSTALL_DIR"/{bin,config,systemd}

# Logs
touch /var/log/evidguard/msmtp.log
chmod 640 /var/log/evidguard/msmtp.log

touch /var/log/evidguard/monitor.log
chmod 640 /var/log/evidguard/monitor.log

# Ficheros de estado v6 (vacíos en instalación limpia)
touch /var/lib/evidguard/last-sent
touch /var/lib/evidguard/last-offset
touch /var/lib/evidguard/last-error-hash

# ── Copiar ficheros ────────────────────────────────────────────────────────────
echo "[INFO] Copiando archivos..."
cp bin/evidguard-report.sh "$INSTALL_DIR/bin/"
cp config/config.conf      "$INSTALL_DIR/config/"
cp systemd/*               "$INSTALL_DIR/systemd/"

chmod 755 "$INSTALL_DIR/bin/evidguard-report.sh"
ln -sf "$INSTALL_DIR/bin/evidguard-report.sh" /usr/local/bin/evidguard-report

# Guardar la ruta detectada en la config instalada
# Usamos delimitador '|' en sed para evitar problemas con rutas que contienen '/'
sed -i "s|RCLONE_GUI_LOG=.*|RCLONE_GUI_LOG=\"${LOG_DETECTADO}\"|" \
    "$INSTALL_DIR/config/config.conf"

# ── Configurar msmtp ───────────────────────────────────────────────────────────
if [[ ! -f /etc/msmtprc ]]; then
    echo "[INFO] Copiando plantilla msmtp → /etc/msmtprc"
    cp config/msmtp.conf /etc/msmtprc
    chmod 600 /etc/msmtprc
    echo ""
    echo "  ⚠️  IMPORTANTE: edita /etc/msmtprc con tu email y App Password"
    echo "     nano /etc/msmtprc"
    echo ""
else
    echo "[INFO] /etc/msmtprc ya existe — no se sobreescribe."
fi

# ── Instalar servicios systemd ─────────────────────────────────────────────────
echo "[INFO] Configurando servicios systemd..."

# Escribir ruta en el .path con delimitador '|' para soportar espacios
sed "s|RCLONE_GUI_LOG_PLACEHOLDER|${LOG_DETECTADO}|g" \
    "$INSTALL_DIR/systemd/evidguard-monitor.path" \
    > /etc/systemd/system/evidguard-monitor.path

cp "$INSTALL_DIR/systemd/evidguard-monitor.service" \
   /etc/systemd/system/evidguard-monitor.service

systemctl daemon-reload
systemctl enable evidguard-monitor.path
systemctl start  evidguard-monitor.path

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              INSTALACIÓN COMPLETADA ✓  (v6)                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Log vigilado:"
echo "    $LOG_DETECTADO"
echo ""
echo "  NOVEDADES v6:"
echo "    • Errores enviados AL INSTANTE (sin esperar fin de copia)"
echo "    • Una sola instancia en espera (flock) → sin carreras de procesos"
echo "    • Seguimiento por offset → solo se analiza contenido nuevo"
echo "    • Todos los errores notificados, sin filtros de ruido"
echo "    • WAIT_MAX=${WAIT_MAX:-300}s (timeout máximo de espera)"
echo ""
echo "  PRÓXIMOS PASOS:"
echo ""
echo "  1. Edita /etc/msmtprc con tu email y App Password:"
echo "       nano /etc/msmtprc"
echo ""
echo "  2. Prueba el envío de correo:"
echo "       echo 'Test EvidGuard v6' | msmtp $MAIL_TO"
echo ""
echo "  3. Prueba el informe completo bajo demanda:"
echo "       evidguard-report"
echo ""
echo "  CONTROL DEL SERVICIO:"
echo "    Estado    : systemctl status evidguard-monitor.path"
echo "    Activar   : systemctl start  evidguard-monitor.path"
echo "    Desactivar: systemctl stop   evidguard-monitor.path"
echo "    Logs live : journalctl -u evidguard-monitor.service -f"
echo "    Log propio: tail -f /var/log/evidguard/monitor.log"
echo ""
