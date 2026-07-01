#!/bin/bash
# EvidGuard LogWatch v6 — evidguard-report.sh
#
# Uso:
#   evidguard-report          → informe bajo demanda (ignora cooldown)
#   evidguard-report --auto   → llamado por el monitor (respeta cooldown)
#
# CORRECCIONES v6 respecto a v5:
#   - Bug "0 doble" en resumen: contar() captura la salida correctamente
#   - Bug "log de horas atrás": el resumen final usa solo el contenido
#     de la copia actual (desde el offset al inicio del --auto hasta el
#     fin de la espera), eliminando get_session_content() por completo

set -uo pipefail

# ── Configuración ──────────────────────────────────────────────────────────────
CONFIG="/opt/evidguard-logwatch/config/config.conf"
[[ -f "$CONFIG" ]] && source "$CONFIG"

MAIL_TO="${MAIL_TO:-root@localhost}"
MAIL_FROM="${MAIL_FROM:-root@localhost}"
MAIL_SUBJECT="${MAIL_SUBJECT:-[EvidGuard] Actividad rclone}"
RCLONE_GUI_LOG="${RCLONE_GUI_LOG:-AUTO}"
COOLDOWN="${COOLDOWN:-600}"
LOG_LINES="${LOG_LINES:-200}"
LOG_INACTIVITY="${LOG_INACTIVITY:-15}"
WAIT_MAX="${WAIT_MAX:-300}"

MONITOR_LOG="/var/log/evidguard/monitor.log"
STATE_DIR="/var/lib/evidguard"
COOLDOWN_FILE="${STATE_DIR}/last-sent"
OFFSET_FILE="${STATE_DIR}/last-offset"
ERR_HASH_FILE="${STATE_DIR}/last-error-hash"
LOCK_FILE="${STATE_DIR}/watcher.lock"
TMPMAIL=$(mktemp /tmp/evidguard-mail-XXXXXX.txt)
MODE="${1:-}"
SEP="─────────────────────────────────────────────"

trap 'rm -f "$TMPMAIL"' EXIT

# ── Funciones de utilidad ──────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MONITOR_LOG"
}

# FIX v6: captura la salida de grep -c en una variable antes de hacer echo.
# grep -c siempre imprime un número (0 o más); exit code 1 solo significa
# "0 coincidencias", no un error real. Con "n=$(...) || n=0" evitamos el
# doble-cero que producía "echo ... | grep -c ... || echo 0".
contar() {
    local texto="$1" patron="$2" n
    n=$(echo "$texto" | grep -c "$patron" 2>/dev/null) || n=0
    echo "$n"
}

# ── Detectar ruta del log (AUTO) ───────────────────────────────────────────────
resolve_log_path() {
    [[ "$RCLONE_GUI_LOG" != "AUTO" ]] && return
    if [[ -d "/root/.cache/com.rclone.manager" ]]; then
        RCLONE_GUI_LOG="/root/.cache/com.rclone.manager/logs/rclone/main_engine.log"
        return
    fi
    for homedir in /home/*/; do
        if [[ -d "${homedir}.cache/com.rclone.manager" ]]; then
            RCLONE_GUI_LOG="${homedir}.cache/com.rclone.manager/logs/rclone/main_engine.log"
            return
        fi
    done
}

resolve_log_path

if [[ ! -f "$RCLONE_GUI_LOG" ]]; then
    log "ERROR: No se encuentra el log: $RCLONE_GUI_LOG"
    log "       Haz una copia con rclone manager para que se cree."
    exit 1
fi

# ── Leer contenido nuevo desde el último offset ────────────────────────────────
# Devuelve las líneas nuevas desde donde se quedó la última vez.
# Actualiza OFFSET_FILE de forma atómica.
read_new_content() {
    local offset=0
    [[ -f "$OFFSET_FILE" ]] && offset=$(< "$OFFSET_FILE") || offset=0

    local size
    size=$(stat -c '%s' "$RCLONE_GUI_LOG" 2>/dev/null) || size=0

    if (( size < offset )); then
        log "Log rotado/truncado (era: ${offset}B → ahora: ${size}B). Reiniciando offset."
        offset=0
        rm -f "$ERR_HASH_FILE"
    fi

    if (( size > offset )); then
        tail -c "+$((offset + 1))" "$RCLONE_GUI_LOG" 2>/dev/null || true
    fi

    echo "$size" > "${OFFSET_FILE}.tmp" && mv "${OFFSET_FILE}.tmp" "$OFFSET_FILE"
}

# ── Leer contenido desde un offset concreto hasta el final actual ─────────────
# FIX v6: usado para el resumen final, garantiza que solo se analiza
# el contenido escrito durante esta copia concreta.
read_from_offset() {
    local from_offset="$1"
    local size
    size=$(stat -c '%s' "$RCLONE_GUI_LOG" 2>/dev/null) || size=0

    if (( size > from_offset )); then
        tail -c "+$((from_offset + 1))" "$RCLONE_GUI_LOG" 2>/dev/null || true
    fi
}

# ── Analizar contenido ─────────────────────────────────────────────────────────
parse_content() {
    local content="$1"

    ERRORES=$(echo "$content" | grep -E " ERROR " || true)

    AVISOS=$(echo "$content" | grep -E " NOTICE" \
        | grep -vE "Can't follow symlink|Allow origin set to \*|Serving remote control" \
        || true)

    STATS=$(echo "$content" | grep -E "Transferred:|Elapsed time:|Errors:" || true)
    INFO=$(echo "$content"  | grep -E " INFO " || true)

    N_ERRORES=$(contar "$ERRORES" "ERROR")
    N_AVISOS=$(contar  "$AVISOS"  "NOTICE")
    N_INFO=$(contar    "$INFO"    "INFO")
}

# ── Construir cuerpo del correo ────────────────────────────────────────────────
build_body() {
    local estado="$1"

    printf 'EvidGuard LogWatch — Informe de actividad rclone\n'
    printf '=================================================\n'
    printf 'Servidor : %s\n'    "$(hostname)"
    printf 'Fecha    : %s\n'    "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Estado   : %s\n\n'  "$estado"

    printf 'RESUMEN\n%s\n'       "$SEP"
    printf '  Errores : %s\n'   "$N_ERRORES"
    printf '  Avisos  : %s\n'   "$N_AVISOS"
    printf '  Info    : %s\n\n' "$N_INFO"

    if [[ -n "$STATS" ]]; then
        printf 'ESTADÍSTICAS DE TRANSFERENCIA\n%s\n%s\n\n' "$SEP" "$STATS"
    fi
    if (( N_ERRORES > 0 )); then
        printf 'ERRORES  (requieren atención)\n%s\n%s\n\n' "$SEP" "$ERRORES"
    fi
    if (( N_AVISOS > 0 )); then
        printf 'AVISOS\n%s\n%s\n\n' "$SEP" "$AVISOS"
    fi
    if (( N_INFO > 0 )); then
        printf 'INFORMACIÓN\n%s\n%s\n\n' "$SEP" "$INFO"
    fi
}

# ── Enviar correo ──────────────────────────────────────────────────────────────
send_mail() {
    local tag="$1" body="$2"
    {
        printf 'To: %s\n'      "$MAIL_TO"
        printf 'From: %s\n'    "$MAIL_FROM"
        printf 'Subject: %s %s — %s\n' \
            "$MAIL_SUBJECT" "$tag" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Date: %s\n'    "$(date -R)"
        printf 'Content-Type: text/plain; charset=UTF-8\n\n'
        echo "$body"
        printf '\n%s\n'              "$SEP"
        printf 'Log completo : %s\n' "$RCLONE_GUI_LOG"
        printf 'EvidGuard LogWatch v6\n'
    } > "$TMPMAIL"

    if msmtp -t < "$TMPMAIL"; then
        log "Correo $tag enviado correctamente a $MAIL_TO."
        return 0
    else
        log "ERROR: Fallo al enviar correo $tag. Revisa /var/log/evidguard/msmtp.log"
        return 1
    fi
}

# ── Enviar errores si son nuevos (deduplicación por hash) ─────────────────────
send_error_if_new() {
    local content="$1"
    parse_content "$content"
    (( N_ERRORES == 0 )) && return 0

    local hash; hash=$(echo "$ERRORES" | md5sum | cut -d' ' -f1)
    local last_hash; last_hash=$(cat "$ERR_HASH_FILE" 2>/dev/null || echo "")

    if [[ "$hash" == "$last_hash" ]]; then
        log "Errores ya notificados (mismo contenido). No se re-envía."
        return 0
    fi

    log "${N_ERRORES} error(es) nuevo(s) → enviando al instante."
    local body; body=$(build_body "⚠  CON ERRORES")
    if send_mail "[ERRORES]" "$body"; then
        echo "$hash" > "$ERR_HASH_FILE"
        date +%s > "$COOLDOWN_FILE"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MODO MANUAL (sin --auto)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" != "--auto" ]]; then
    log "Informe bajo demanda solicitado."

    # En modo manual mostramos las últimas LOG_LINES líneas
    SESSION=$(tail -n "$LOG_LINES" "$RCLONE_GUI_LOG")
    parse_content "$SESSION"

    if (( N_ERRORES > 0 )); then TAG="[ERRORES]"; ESTADO="⚠  CON ERRORES"
    else                          TAG="[OK]";      ESTADO="✓  CORRECTO"
    fi

    BODY=$(build_body "$ESTADO")
    send_mail "$TAG" "$BODY"
    exit $?
fi

# ══════════════════════════════════════════════════════════════════════════════
# MODO --auto (llamado por systemd .path)
#
# FIX v6 — el resumen final usa SOLO el contenido de esta copia:
#   Se guarda el offset al inicio de la Fase 1 (START_OFFSET).
#   Al final, se relee desde START_OFFSET hasta el final del log.
#   Así el resumen refleja exactamente lo que ocurrió en esta copia,
#   sin importar lo que haya en el log de horas anteriores.
# ══════════════════════════════════════════════════════════════════════════════

# ── Guardar offset de inicio ANTES de Fase 1 ──────────────────────────────────
# FIX v6: este offset delimita el inicio de la copia actual
START_OFFSET=0
[[ -f "$OFFSET_FILE" ]] && START_OFFSET=$(< "$OFFSET_FILE") || START_OFFSET=0
# Si el log es más corto (rotación), el inicio es 0
CUR_SIZE=$(stat -c '%s' "$RCLONE_GUI_LOG" 2>/dev/null) || CUR_SIZE=0
(( START_OFFSET > CUR_SIZE )) && START_OFFSET=0

# ── Fase 1: comprobación inmediata de errores ──────────────────────────────────
log "Cambio detectado en el log. Comprobando errores inmediatamente..."
NEW_CONTENT=$(read_new_content)

if [[ -n "$NEW_CONTENT" ]]; then
    send_error_if_new "$NEW_CONTENT"
else
    log "Sin contenido nuevo (offset ya actualizado)."
fi

# ── Fase 2: espera de inactividad (instancia única con flock) ──────────────────
exec {LOCKFD}>"$LOCK_FILE" 2>/dev/null || { log "No se pudo abrir el lock file."; exit 0; }

if ! flock -n "$LOCKFD"; then
    log "Otra instancia ya gestiona el fin de copia. Fase 1 completada."
    exit 0
fi

log "Esperando fin de copia (${LOG_INACTIVITY}s de silencio, máx ${WAIT_MAX}s)..."

WAITED=0
LAST_SIZE=$(stat -c '%s' "$RCLONE_GUI_LOG" 2>/dev/null) || LAST_SIZE=0

while true; do
    sleep "$LOG_INACTIVITY"
    WAITED=$(( WAITED + LOG_INACTIVITY ))
    CURR_SIZE=$(stat -c '%s' "$RCLONE_GUI_LOG" 2>/dev/null) || CURR_SIZE=0

    LOOP_NEW=$(read_new_content)
    [[ -n "$LOOP_NEW" ]] && send_error_if_new "$LOOP_NEW"

    if (( CURR_SIZE == LAST_SIZE )); then
        log "Log estable tras ${WAITED}s. Generando resumen de copia."
        break
    fi

    if (( WAITED >= WAIT_MAX )); then
        log "Timeout ${WAIT_MAX}s alcanzado. Generando resumen de todas formas."
        break
    fi

    LAST_SIZE="$CURR_SIZE"
done

# ── Cooldown: solo aplica al resumen OK, nunca a los errores ──────────────────
NOW=$(date +%s)
if [[ -f "$COOLDOWN_FILE" ]]; then
    LAST=$(< "$COOLDOWN_FILE")
    ELAPSED=$(( NOW - LAST ))
    if (( ELAPSED < COOLDOWN )); then
        log "Cooldown activo: faltan $(( COOLDOWN - ELAPSED ))s. No se envía resumen."
        exit 0
    fi
fi

# ── Resumen final: SOLO el contenido de esta copia ────────────────────────────
# FIX v6: lee desde START_OFFSET (guardado antes de Fase 1) hasta el final
SESSION=$(read_from_offset "$START_OFFSET")
parse_content "$SESSION"

if (( N_ERRORES > 0 )); then TAG="[ERRORES]"; ESTADO="⚠  CON ERRORES"
else                          TAG="[OK]";      ESTADO="✓  CORRECTO"
fi

BODY=$(build_body "$ESTADO")
if send_mail "$TAG" "$BODY"; then
    date +%s > "$COOLDOWN_FILE"
fi
