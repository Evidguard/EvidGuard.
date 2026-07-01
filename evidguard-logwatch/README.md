# EvidGuard LogWatch v6

Monitor de actividad de rclone manager con notificación por correo.

## ¿Qué hace?

Vigila el log de rclone manager. Al detectar errores los envía **al instante**.
Cuando la copia termina, espera unos segundos de silencio y envía un resumen
completo con estadísticas de transferencia.

## Novedades v6 frente a v4

| Problema (v4)                                           | Solución (v6)                                              |
|---------------------------------------------------------|------------------------------------------------------------|
| Los errores esperaban LOG_INACTIVITY antes de enviarse  | Fase 1 inmediata: errores al instante, sin espera          |
| Múltiples instancias podían correr a la vez             | flock garantiza una sola instancia en espera               |
| Se re-analizaba todo el log en cada disparo             | Offset de bytes: solo se procesa el contenido nuevo        |
| El mismo error podía enviarse varias veces              | Deduplicación por hash MD5 del bloque de errores           |
| Errores "too short" y "directory not found" se ignoraban| Todos los errores llegan al correo, sin filtros            |
| WAIT_MAX hardcodeado a 3600s                            | WAIT_MAX configurable en config.conf (default: 300s)       |
| uninstall.sh con versión incorrecta (v3)                | Corregido a v6                                             |

## Flujo de ejecución (modo --auto)

```
rclone escribe en el log
        │
        ▼
systemd .path detecta el cambio
        │
        ▼
  ┌─────────────────────────────────────┐
  │  FASE 1 — INMEDIATA (siempre)       │
  │  Lee bytes nuevos desde último      │
  │  offset → si hay ERROR → envía      │
  │  al instante (dedup por hash)       │
  └─────────────────────────────────────┘
        │
        ▼
  ┌─────────────────────────────────────┐
  │  FASE 2 — ESPERA (solo 1 instancia) │
  │  flock: si ya hay otra esperando    │──→ EXIT (Fase 1 fue suficiente)
  │  → Bucle: cada LOG_INACTIVITY seg.  │
  │    comprueba errores nuevos         │
  │  → Rompe si log lleva              │
  │    LOG_INACTIVITY seg. sin cambios  │
  │    o se alcanza WAIT_MAX            │
  └─────────────────────────────────────┘
        │
        ▼
  ¿Cooldown activo?
  │ Sí → EXIT (errores ya se enviaron en Fase 1)
  │ No ↓
  Envía resumen completo de la sesión
```

## Instalación

```bash
# 1. Edita la configuración con tu email
nano config/config.conf

# 2. Instala (requiere root)
sudo ./install.sh
```

## Configuración

Edita `config/config.conf` antes de instalar:

```bash
MAIL_TO="tu@gmail.com"        # Destinatario
MAIL_FROM="tu@gmail.com"      # Remitente
COOLDOWN=600                  # Segundos mínimos entre correos de resumen
LOG_LINES=200                 # Líneas de fallback si no hay marcador de sesión
LOG_INACTIVITY=15             # Segundos de silencio = copia terminada
WAIT_MAX=300                  # Timeout máximo de espera (5 min para copias cortas)
```

> **`LOG_INACTIVITY`**: tiempo de silencio para confirmar que la copia acabó.
> Si rclone no escribe nada durante LOG_INACTIVITY segundos, se considera terminado.
>
> **`WAIT_MAX`**: tope absoluto. Si la copia dura más de lo esperado, el resumen
> se envía igualmente al llegar a este límite. Para copias de ~2 min, 300s sobra.

## Prueba rápida

```bash
# Informe bajo demanda (ignora cooldown)
evidguard-report

# Ver log del monitor en tiempo real
tail -f /var/log/evidguard/monitor.log

# Ver actividad de systemd en tiempo real
journalctl -u evidguard-monitor.service -f
```

## Desinstalación

```bash
sudo ./uninstall.sh
```

## Requisitos

- Ubuntu 20.04+ / Debian 11+ / Raspberry Pi OS
- Bash 4.1+ (incluido en las distros anteriores)
- `msmtp` (se instala automáticamente)
- Cuenta Gmail con App Password configurada en `/etc/msmtprc`
