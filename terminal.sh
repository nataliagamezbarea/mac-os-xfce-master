#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

terminal_konsole() {
    step "Configurando Konsole"
    mkdir -p ~/.local/share/konsole

    cat > ~/.local/share/konsole/"$TEMA_KONSOLE".colorscheme << KONEOF
[General]
Description=Tema Ventura Konsole
Opacity=0.88
Wallpaper=

[Background]
Blur=1
Color=28,28,32

[BackgroundIntense]
Color=28,28,32

[Foreground]
Color=220,220,220

[ForegroundIntense]
Color=248,248,248

[Color0]
Color=50,52,58

[Color0Intense]
Color=66,68,74

[Color1]
Color=240,113,120

[Color1Intense]
Color=255,140,150

[Color2]
Color=153,209,111

[Color2Intense]
Color=173,229,131

[Color3]
Color=229,192,123

[Color3Intense]
Color=249,212,143

[Color4]
Color=130,170,230

[Color4Intense]
Color=150,190,250

[Color5]
Color=200,150,220

[Color5Intense]
Color=220,170,240

[Color6]
Color=90,200,210

[Color6Intense]
Color=110,220,230

[Color7]
Color=190,192,196

[Color7Intense]
Color=235,237,240

[Color8]
Color=80,82,88

[Color8Intense]
Color=100,102,108

[Color9]
Color=240,113,120

[Color9Intense]
Color=255,140,150

[Color10]
Color=153,209,111

[Color10Intense]
Color=173,229,131

[Color11]
Color=229,192,123

[Color11Intense]
Color=249,212,143

[Color12]
Color=130,170,230

[Color12Intense]
Color=150,190,250

[Color13]
Color=200,150,220

[Color13Intense]
Color=220,170,240

[Color14]
Color=90,200,210

[Color14Intense]
Color=110,220,230

[Color15]
Color=218,220,224

[Color15Intense]
Color=248,250,254

[Selection]
Color=248,248,248

[SelectionBackground]
Color=100,140,200
KONEOF

    printf '[Appearance]\nColorScheme=%s\nFont=MesloLGS NF,12,-1,5,50,0,0,0,0,0\n[General]\nName=Ventura\nParent=FALLBACK/\n' \
        "$TEMA_KONSOLE" > ~/.local/share/konsole/Ventura.profile
    kwriteconfig5 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Ventura.profile" 2>/dev/null || true
    info "Konsole configurado con tema macOS"
}

terminal_xfce4_default_konsole() {
    step "Estableciendo Konsole como terminal por defecto"
    mkdir -p ~/.config/xfce4
    if grep -q '^TerminalEmulator=' ~/.config/xfce4/helpers.rc 2>/dev/null; then
        sed -i 's/^TerminalEmulator=.*/TerminalEmulator=konsole/' ~/.config/xfce4/helpers.rc
    else
        echo 'TerminalEmulator=konsole' >> ~/.config/xfce4/helpers.rc
    fi
    if command -v exo-preferred-applications &>/dev/null; then
        exo-preferred-applications --terminal konsole 2>/dev/null || true
    fi
    # Forzar Qt5 a usar tema GTK3 oscuro (barra de menú, pestañas, decoraciones)
    # QT_QPA_PLATFORMTHEME=gtk3 lee ~/.config/gtk-3.0/settings.ini directamente,
    # a diferencia de QT_STYLE_OVERRIDE=gtk2 que necesita un tema GTK2 aparte.
    apt_silencioso install qt5-gtk-platformtheme 2>/dev/null || \
        apt_silencioso install qt5-qpa-gtk-platform-theme 2>/dev/null || true

    # 1) Archivos de perfil de shell (para terminales)
    for rc in ~/.profile ~/.bashrc ~/.zshrc; do
        if [ -f "$rc" ] && [ -w "$rc" ]; then
            grep -q 'QT_QPA_PLATFORMTHEME' "$rc" 2>/dev/null || \
                echo 'export QT_QPA_PLATFORMTHEME=gtk3' >> "$rc"
        fi
    done

    # 2) /etc/environment para sesiones nuevas (PAM)
    if [ -w /etc/environment ]; then
        grep -q 'QT_QPA_PLATFORMTHEME' /etc/environment 2>/dev/null || \
            echo 'QT_QPA_PLATFORMTHEME=gtk3' >> /etc/environment
    fi

    # 3) systemd user environment (sesiones con systemd)
    mkdir -p ~/.config/environment.d
    echo 'QT_QPA_PLATFORMTHEME=gtk3' > ~/.config/environment.d/qt.conf
    if command -v systemctl &>/dev/null; then
        systemctl --user set-environment QT_QPA_PLATFORMTHEME=gtk3 2>/dev/null || true
    fi

    # 4) Modificar el .desktop de Konsole para que funcione aunque se abra desde el panel
    if [ -f /usr/share/applications/org.kde.konsole.desktop ]; then
        mkdir -p ~/.local/share/applications
        cp -n /usr/share/applications/org.kde.konsole.desktop ~/.local/share/applications/ 2>/dev/null || true
        local konsole_desk="$HOME/.local/share/applications/org.kde.konsole.desktop"
        if [ -f "$konsole_desk" ]; then
            sed -i 's|^Exec=konsole|Exec=env QT_QPA_PLATFORMTHEME=gtk3 konsole|' "$konsole_desk"
            sed -i 's|^Exec=konsole-wrapper|Exec=env QT_QPA_PLATFORMTHEME=gtk3 konsole-wrapper|' "$konsole_desk"
        fi
    fi

    export QT_QPA_PLATFORMTHEME=gtk3

    # Configurar fuente Nerd Font para xfce4-terminal
    local xfce_config="$HOME/.config/xfce4/terminal/terminalrc"
    if [ -f "$xfce_config" ]; then
        sed -i 's/^FontName=.*/FontName=MesloLGS NF 11/' "$xfce_config" 2>/dev/null || true
        if ! grep -q '^FontName=' "$xfce_config"; then
            echo 'FontName=MesloLGS NF 11' >> "$xfce_config"
        fi
    fi

    info "Konsole es ahora la terminal por defecto (Ctrl+Alt+T)"
}

terminal_zsh() {
    step "Instalando Zsh, Oh-My-Zsh y Oh-My-Posh"
    apt_silencioso install zsh
    echo "/usr/bin/zsh" | sudo tee -a /etc/shells >/dev/null 2>/dev/null || true
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-autosuggestions    ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions    2>/dev/null || true
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting 2>/dev/null || true
    git clone https://github.com/zsh-users/zsh-completions        ~/.oh-my-zsh/custom/plugins/zsh-completions        2>/dev/null || true
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' ~/.zshrc
    mkdir -p ~/.local/bin
    curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
    # Asegurar que ~/.local/bin esta en el PATH de todas las shells
    for rc in ~/.bashrc ~/.profile; do
        grep -q 'local/bin' "$rc" 2>/dev/null || \
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    done
    export PATH="$HOME/.local/bin:$PATH"
    mkdir -p ~/.config
    curl -s -o ~/.config/ohmyposh.json \
        https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/gmay.omp.json
    grep -q 'oh-my-posh init zsh' ~/.zshrc || \
        echo 'command -v oh-my-posh &>/dev/null && eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh.json)"' >> ~/.zshrc
    grep -q 'oh-my-posh init bash' ~/.bashrc || \
        echo 'command -v oh-my-posh &>/dev/null && eval "$(oh-my-posh init bash --config ~/.config/ohmyposh.json)"' >> ~/.bashrc
    sudo usermod --shell /usr/bin/zsh "$USER"
    grep -q "exec zsh" ~/.bashrc || echo 'if [[ $- == *i* ]] && [ -z "$ZSH_VERSION" ]; then exec zsh; fi' >> ~/.bashrc
    # Asegurar que ~/.local/bin esté en el PATH de zsh antes del eval de oh-my-posh
    if ! grep -q '^export PATH=.*\.local/bin' ~/.zshrc 2>/dev/null; then
        sed -i '1s|^|export PATH="$HOME/.local/bin:$PATH"\n|' ~/.zshrc
    fi

    # Refrescar caché de fuentes y aplicar Nerd Font en la terminal actual
    fc-cache -f 2>/dev/null || true

    # Configurar xfce4-terminal para usar MesloLGS NF
    local xfce_config="$HOME/.config/xfce4/terminal/terminalrc"
    if [ -f "$xfce_config" ]; then
        sed -i 's/^FontName=.*/FontName=MesloLGS NF 11/' "$xfce_config" 2>/dev/null || true
    fi

    # Intentar cambiar al perfil Ventura en Konsole (tiene MesloLGS NF)
    if [ -n "$KONSOLE_VERSION" ] && command -v konsoleprofile &>/dev/null; then
        konsoleprofile Profile=Ventura 2>/dev/null || true
    fi

    # Recargar oh-my-posh en la sesion actual
    if command -v oh-my-posh &>/dev/null; then
        eval "$(oh-my-posh init bash --config ~/.config/ohmyposh.json)" 2>/dev/null || true
    fi
    info "Zsh + Oh-My-Zsh + Oh-My-Posh instalados"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && TEMA_KONSOLE="Ventura-Light" || TEMA_KONSOLE="Ventura-Dark"
    export MODO TEMA_KONSOLE

    paso="${2:-todo}"
    case "$paso" in
        konsole) terminal_konsole ;;
        zsh)     terminal_zsh ;;
        default) terminal_xfce4_default_konsole ;;
        todo)
            terminal_konsole
            terminal_xfce4_default_konsole
            terminal_zsh
            ;;
    esac
fi
