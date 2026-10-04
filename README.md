# Script de Configuración del Panel XFCE

Este script configura automáticamente el panel XFCE, Plank y varias funciones del sistema.

## Opciones de Ejecución

### Ejecutar todo (completo)
```bash
bash panel.sh
```
Configura todo el sistema:
- Panel XFCE con tema macOS
- Plank dock con launchers
- Brave como navegador predeterminado
- Safari usando Brave con icono de Safari
- Gestor wifi al inicio
- Ocultar gestor de llaves de la bandeja

### Opciones individuales
```bash
# Configurar solo el panel XFCE
bash panel.sh config

# Configurar solo Plank
bash panel.sh plank

# Configurar solo el navegador (Safari/Brave)
bash panel.sh navegador

# Desactivar el gestor de llaves
bash panel.sh desactivar-keyring

# Crear copia de seguridad de Plank
bash panel.sh backup

# Reiniciar el panel
bash panel.sh reiniciar
```

## Configuraciones Adicionales

### Configurar comportamiento de la tapa (requiere sudo)
```bash
sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
```

### Configurar arranque silencioso (requiere sudo)
```bash
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 vga=current"/' /etc/default/grub
sudo update-grub
```

## Características

- **Navegador predeterminado**: Brave configurado como navegador del sistema
- **Safari**: Usa Brave internamente pero mantiene icono de Safari
- **Gestor wifi**: Se inicia automáticamente al arranque
- **Gestor de llaves**: Se puede desactivar completamente
- **VirtualBox**: Funciona normalmente (sin agrupado forzado)
- **Plank**: Dock estilo macOS con tema transparente

## Solución de Problemas

Si algo no funciona correctamente:
1. Ejecuta la opción específica para ese componente
2. Verifica que los archivos de configuración se crearon correctamente
3. Reinicia el panel XFCE: `xfce4-panel -r`
4. Reinicia Plank: `pkill plank && plank`

## Archivos Modificados

- `~/.config/xfce4/` - Configuración del panel XFCE
- `~/.config/plank/` - Configuración del dock Plank
- `~/.local/share/applications/` - Launchers modificados
- `~/.local/bin/` - Scripts wrappers si es necesario
