# SpyGuard Control Panel v2.2.1

Panel de control profesional para gestionar los servicios systemd de SpyGuard.

## Instalación rápida

```bash
unzip spyguard-cp-v2.2.1.zip
cd spyguard-cp-v2
sudo ./install.sh
```

## Ejecución

- **Doble clic en el icono del Desktop** (pide contraseña vía pkexec)
- **Menú de aplicaciones** → SpyGuard Control Panel
- **Terminal:** `spyguard-cp`

## Si no se ejecuta (diagnóstico)

1. **Revisa los logs:**
   ```bash
   cat /tmp/spyguard-wrapper.log
   cat /tmp/spyguard-control-panel.log
   ```

2. **Verifica permisos de ejecución:**
   ```bash
   sudo chmod +x install.sh uninstall.sh bin/spyguard-cp
   ```

3. **Prueba ejecución manual:**
   ```bash
   sudo python3 /opt/spyguard-cp/lib/spyguard_control_panel.py
   ```

4. **Si falta tkinter:**
   ```bash
   sudo apt install python3-tk
   ```

## Desinstalación

```bash
sudo /opt/spyguard-cp/uninstall.sh
```

## Personalizar logo

Reemplaza `assets/logo.png` antes de instalar, o copia tu PNG después:
```bash
sudo cp mi-logo.png /opt/spyguard-cp/assets/logo.png
```
