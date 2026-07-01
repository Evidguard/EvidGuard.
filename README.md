# EvidGuard Forensic Toolkit

> **Conjunto de herramientas forenses para Raspberry Pi.**  
> Diseñado para análisis forense de campo, con write-blocking automático, panel de control de servicios y monitorización de transferencias en tiempo real.

---

## Índice

- [Descripción general](#descripción-general)
- [Requisitos previos](#requisitos-previos)
- [Dependencia principal: Rclone Manager](#dependencia-principal-rclone-manager)
- [Herramientas incluidas](#herramientas-incluidas)
  - [EVG Write-Blocker (Block)](#1-evg-write-blocker-block)
  - [SpyGuard Control Panel](#2-spyguard-control-panel)
  - [EvidGuard LogWatch](#3-evidguard-logwatch)
- [Flujo de trabajo recomendado](#flujo-de-trabajo-recomendado)
- [Notas forenses](#notas-forenses)

---

## Descripción general

Este toolkit está pensado para operaciones forenses sobre **Raspberry Pi** (probado con Raspberry Pi OS / Debian 11+). Agrupa tres herramientas complementarias que trabajan juntas para proteger la integridad de las evidencias digitales durante la adquisición y transferencia de datos:

1. **EVG Write-Blocker** — bloquea automáticamente en modo solo lectura cualquier dispositivo de almacenamiento que se conecte, protegiendo las evidencias frente a escrituras accidentales.
2. **SpyGuard Control Panel** — interfaz gráfica para gestionar los servicios de SpyGuard (backend, frontend y watchers) desde el escritorio de la Raspberry Pi.
3. **EvidGuard LogWatch** — monitoriza el log de Rclone Manager y envía notificaciones por correo en tiempo real sobre errores y resúmenes de transferencia.

---

## Requisitos previos

| Requisito | Versión mínima |
|---|---|
| Raspberry Pi OS / Debian / Ubuntu | 11 Bullseye / 20.04 LTS |
| Bash | 4.1+ |
| Python 3 + Tkinter | Incluido en Raspberry Pi OS |
| `util-linux` (`blockdev`) | Incluido en el sistema |
| `udev` | Incluido en el sistema |
| `msmtp` | Se instala automáticamente |
| `python3-pil` (Pillow) | Se instala automáticamente |

Todas las herramientas detectan e instalan sus dependencias durante el proceso de instalación.

---

## Dependencia principal: Rclone Manager

Las tres herramientas están diseñadas para usarse **en conjunto con Rclone Manager**, que debe instalarse por separado. Rclone Manager es la interfaz gráfica oficial de rclone y es el componente responsable de gestionar y ejecutar las transferencias de datos entre la Raspberry Pi y el almacenamiento en la nube o remoto.

> 🔗 **Descarga e instrucciones de instalación:** [https://github.com/Zarestia-Dev/rclone-manager](rclonemanager)

EVG Write-Blocker protege los dispositivos fuente mientras Rclone Manager realiza la copia, y EvidGuard LogWatch vigila el log generado por Rclone Manager para notificar sobre el estado de cada transferencia.

---

## Herramientas incluidas

---

### 1. EVG Write-Blocker (Block)

**Carpeta:** `Block-fixed-v4/`

Write-blocker software al estilo forense, equivalente funcional al "UnBlock" de CAINE Linux, adaptado para Raspberry Pi. Garantiza que cualquier dispositivo de almacenamiento conectado quede en modo **solo lectura** de forma automática e inmediata, protegiendo la integridad de las evidencias.

#### Cómo funciona

El sistema opera en tres capas complementarias:

- **udev (tiempo real):** Una regla udev (`80-evg-blockdev.rules`) intercepta el evento `add` de cualquier dispositivo de bloque recién conectado (USB, SATA, NVMe, tarjetas MMC externas) y ejecuta `evg-setro`, que aplica `blockdev --setro` sobre el dispositivo en milisegundos. Excluye explícitamente `mmcblk0` (la SD del sistema en RPi) y dispositivos virtuales (`loop`, `ram`, `zram`).

- **systemd (arranque):** El servicio `evg-blockdev.service` ejecuta `evg-blockall` durante el arranque del sistema, antes de que se monten los sistemas de ficheros locales (`Before=local-fs.target`). Esto asegura que cualquier dispositivo que estuviera conectado antes del arranque también quede protegido.

- **GUI (gestión manual):** La herramienta gráfica `evg-unblock` permite al perito forense ver todos los dispositivos conectados con su estado actual (RO/RW), cambiar temporalmente un dispositivo a lectura/escritura cuando sea necesario (por ejemplo, para formatear un disco destino), y volver a bloquearlo. Cada acción queda registrada en el log forense junto con metadatos del dispositivo (fabricante, modelo, número de serie, tamaño, tipo de sistema de ficheros).

El log forense completo se escribe en `/var/log/evg-blockdev.log`, con marca de tiempo para cada evento.

#### Instalación

```bash
cd Block-fixed-v4/
sudo ./install.sh
```

El instalador realiza automáticamente:
- Instalación de dependencias (`python3-tk`, `python3-pil`, `util-linux`, `udev`)
- Copia de scripts al sistema (`/usr/local/sbin/`, `/usr/local/bin/`)
- Instalación y recarga de la regla udev
- Habilitación del servicio systemd en el arranque
- Creación del acceso directo en el escritorio
- Aplicación inmediata del bloqueo a todos los dispositivos presentes

> ⚠️ Se recomienda reiniciar tras la instalación para confirmar el servicio de arranque: `sudo reboot`

#### Uso

```bash
# Interfaz gráfica (recomendado)
sudo evg-unblock

# Bloquear todos los dispositivos manualmente
sudo evg-blockall

# Bloquear un disco específico
sudo blockdev --setro /dev/sdb

# Desbloquear un disco específico (usar con precaución)
sudo blockdev --setrw /dev/sdb

# Ver el registro forense
cat /var/log/evg-blockdev.log
```

#### Dispositivos compatibles

| Tipo | Patrón | Notas |
|---|---|---|
| USB / SATA | `/dev/sd[a-z]` | Incluye particiones |
| NVMe (adaptadores USB) | `/dev/nvme[0-9]n[0-9]` | Incluye particiones |
| MMC / SD externas | `/dev/mmcblk[1-9]` | Excluye `mmcblk0` (sistema) |

#### Desinstalación

```bash
sudo ./uninstall.sh
```

---

### 2. SpyGuard Control Panel

**Carpeta:** `spyguard-cp-v2_2_1/`

Panel de control gráfico para gestionar los servicios systemd de **SpyGuard** (`spyguard-backend`, `spyguard-frontend`, `spyguard-watchers`) directamente desde el escritorio de la Raspberry Pi.

#### Cómo funciona

La aplicación está desarrollada en Python 3 con Tkinter y proporciona:

- **Monitor de estado en tiempo real:** Muestra el estado de cada servicio (activo, inactivo, iniciando, fallido) mediante LEDs animados con pulso y contadores de uptime en vivo, con refresco automático cada 5 segundos.
- **Control centralizado:** Botones para iniciar o detener todos los servicios en secuencia ordenada. El arranque sigue un orden específico: primero el backend (con health check del puerto 8443), luego el frontend y finalmente los watchers, con reintentos automáticos en caso de fallo.
- **Reinicio individual:** Cada tarjeta de servicio incluye un botón de reinicio con seguimiento del estado hasta la estabilización.
- **Acceso rápido al frontend y backend:** Abre directamente las interfaces web de SpyGuard en el navegador del sistema (`http://localhost:8000` y `https://localhost:8443`).
- **Consola de logs integrada:** Muestra en tiempo real los eventos de arranque, parada y errores de los servicios, con código de color por severidad.
- **Gestión de certificados SSL:** Copia automáticamente los certificados necesarios al iniciar todos los servicios.
- **Notificaciones de escritorio:** Envía notificaciones del sistema al usuario al completar operaciones de inicio/parada.

El panel se lanza con privilegios de administrador mediante `pkexec` (con diálogo gráfico de contraseña) o `sudo` como alternativa, sin necesidad de abrir una terminal. Es compatible con Wayland y X11, e incluye detección y paso explícito de las variables de entorno gráfico para sistemas con polkit 0.120+ (Debian 13).

#### Instalación

```bash
cd spyguard-cp-v2_2_1/
sudo ./install.sh
```

El instalador:
- Verifica e instala `python3-tk` si es necesario
- Copia la aplicación a `/opt/spyguard-cp/`
- Crea el ejecutable global `spyguard-cp`
- Instala el acceso directo en el menú de aplicaciones y en el escritorio

> SpyGuard debe estar instalado en el sistema previamente para que el panel pueda gestionar sus servicios.

#### Uso

```bash
# Desde terminal
spyguard-cp

# O directamente con Python
sudo python3 /opt/spyguard-cp/lib/spyguard_control_panel.py
```

También puede lanzarse con doble clic en el icono del escritorio o desde el menú de aplicaciones (`Sistema > Seguridad > SpyGuard Control Panel`).

**Atajos de teclado:**

| Atajo | Acción |
|---|---|
| `F5` | Refrescar estado de servicios |
| `Ctrl+Q` | Cerrar el panel |

#### Diagnóstico

```bash
# Log del wrapper de lanzamiento
cat /tmp/spyguard-wrapper.log

# Log de la aplicación Python
cat /tmp/spyguard-control-panel.log
```

#### Desinstalación

```bash
sudo /opt/spyguard-cp/uninstall.sh
```

---

### 3. EvidGuard LogWatch

**Carpeta:** `evidguard-logwatch-v6/`

Monitor de actividad de Rclone Manager con notificación por correo electrónico. Vigila el log de Rclone Manager en tiempo real y envía alertas al instante cuando detecta errores, además de un resumen completo al finalizar cada sesión de copia.

#### Cómo funciona

El sistema opera en dos fases diferenciadas, activadas por un path unit de systemd que detecta cualquier modificación en el log de Rclone Manager:

```
Rclone Manager escribe en el log
         │
         ▼
systemd .path detecta el cambio
         │
         ▼
┌────────────────────────────────────┐
│  FASE 1 — INMEDIATA (siempre)      │
│  Lee solo los bytes nuevos desde   │
│  el último offset → si contiene    │
│  ERROR → envía correo al instante  │
│  (deduplicación por hash MD5)      │
└────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  FASE 2 — ESPERA (una instancia)   │
│  flock: garantiza una sola         │
│  instancia en espera               │
│  → Bucle cada LOG_INACTIVITY seg.  │
│  → Sale cuando el log lleva        │
│    LOG_INACTIVITY seg. sin cambios │
│    o se alcanza WAIT_MAX           │
└────────────────────────────────────┘
         │
         ▼
  ¿Cooldown activo?
  Sí → EXIT (errores ya notificados)
  No → Envía resumen completo
```

Características técnicas destacadas:
- **Seguimiento por offset de bytes:** Solo procesa el contenido nuevo del log en cada disparo, evitando reanálisis del historial completo.
- **Deduplicación por hash MD5:** El mismo bloque de errores no se notifica más de una vez.
- **Una sola instancia en espera:** `flock` garantiza que no haya condiciones de carrera entre procesos concurrentes.
- **Detección automática del log:** Localiza automáticamente la ruta del log de Rclone Manager según el usuario del sistema.
- **Envío de correo con `msmtp`:** Compatible con Gmail mediante App Passwords (autenticación en dos pasos).

#### Instalación

**Paso 1 — Editar la configuración:**

```bash
nano config/config.conf
```

Parámetros principales:

| Parámetro | Descripción | Valor por defecto |
|---|---|---|
| `MAIL_TO` | Email destinatario | — |
| `MAIL_FROM` | Email remitente (cuenta Gmail) | — |
| `COOLDOWN` | Segundos mínimos entre correos de resumen | `600` |
| `LOG_INACTIVITY` | Segundos de silencio = copia terminada | `15` |
| `WAIT_MAX` | Timeout máximo antes de forzar el resumen | `300` |
| `LOG_LINES` | Líneas de fallback si no hay marcador de sesión | `200` |
| `RCLONE_GUI_LOG` | Ruta del log (`AUTO` para detección automática) | `AUTO` |

**Paso 2 — Instalar:**

```bash
sudo ./install.sh
```

**Paso 3 — Configurar Gmail App Password:**

```bash
# Editar con tus credenciales de Gmail
sudo nano /etc/msmtprc

# Probar el envío
echo 'Test EvidGuard' | msmtp tu@gmail.com
```

> Para obtener un App Password de Gmail, activa la verificación en dos pasos en tu cuenta y genera una contraseña en [https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords). El password son 16 caracteres sin espacios.

#### Uso

```bash
# Informe bajo demanda (ignora el cooldown)
evidguard-report

# Ver el log del monitor en tiempo real
tail -f /var/log/evidguard/monitor.log

# Ver actividad de systemd en tiempo real
journalctl -u evidguard-monitor.service -f

# Gestión del servicio
systemctl status evidguard-monitor.path
systemctl start  evidguard-monitor.path
systemctl stop   evidguard-monitor.path
```

#### Desinstalación

```bash
sudo ./uninstall.sh
```

---

## Flujo de trabajo recomendado

El siguiente flujo describe el uso típico de las tres herramientas durante una adquisición forense de campo:

```
1. Arrancar la Raspberry Pi
   └─ evg-blockdev.service bloquea en RO todos los dispositivos presentes

2. Conectar el dispositivo a peritar (USB, HDD, SD card...)
   └─ udev detecta el dispositivo y evg-setro lo bloquea en RO automáticamente
   └─ El evento queda registrado en /var/log/evg-blockdev.log

3. (Opcional) Si necesitas desbloquear el dispositivo destino para la copia:
   └─ Abrir EVG UnBlock (sudo evg-unblock)
   └─ Cambiar el disco destino a RW temporalmente
   └─ El disco origen siempre permanece en RO

4. Iniciar SpyGuard desde el panel de control
   └─ spyguard-cp → "Iniciar Todo"
   └─ Verificar que backend, frontend y watchers están activos

5. Iniciar la copia con Rclone Manager
   └─ EvidGuard LogWatch vigila el log automáticamente
   └─ Cualquier error se notifica por correo al instante
   └─ Al finalizar la copia, se envía un resumen con estadísticas

6. Al terminar, volver a bloquear el dispositivo destino
   └─ EVG UnBlock → cambiar a RO
   └─ O: sudo evg-blockall
```

---

## Notas forenses

- El `mmcblk0` (tarjeta SD del sistema de la Raspberry Pi) está excluido explícitamente de todos los bloqueos para no interferir con el sistema operativo.
- Todos los eventos de bloqueo/desbloqueo se registran con marca de tiempo, metadatos del dispositivo (fabricante, modelo, número de serie) y el origen de la acción (arranque del sistema, udev o GUI).
- El uso de `blockdev --setro` es un write-blocker software. Para entornos que requieran write-blocking hardware certificado, este sistema puede complementar (pero no sustituir) un bloqueador hardware.
- Los logs de EvidGuard LogWatch incluyen únicamente la actividad de Rclone Manager; no acceden ni modifican los datos transferidos.
