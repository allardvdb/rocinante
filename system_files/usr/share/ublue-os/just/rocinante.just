# vim: set ft=make :
# Rocinante custom ujust recipes

# Configure YubiKey for GPG and SSH authentication
[group('Rocinante')]
setup-yubikey-ssh:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    echo "${b}Setting up YubiKey for GPG/SSH authentication...${n}"

    # Create scdaemon.conf for reliable YubiKey detection
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg

    if [[ ! -f ~/.gnupg/scdaemon.conf ]]; then
        echo "# Disable scdaemon's built-in CCID driver to prevent race condition with pcscd" > ~/.gnupg/scdaemon.conf
        echo "disable-ccid" >> ~/.gnupg/scdaemon.conf
        echo "" >> ~/.gnupg/scdaemon.conf
        echo "# Allow shared access to the card (needed when opensc/other apps also use it)" >> ~/.gnupg/scdaemon.conf
        echo "pcsc-shared" >> ~/.gnupg/scdaemon.conf
        echo "Created ~/.gnupg/scdaemon.conf"
    else
        echo "~/.gnupg/scdaemon.conf already exists, skipping"
    fi

    # Update gpg-agent.conf for SSH support
    if ! grep -q "enable-ssh-support" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
        echo "" >> ~/.gnupg/gpg-agent.conf
        echo "# SSH support" >> ~/.gnupg/gpg-agent.conf
        echo "enable-ssh-support" >> ~/.gnupg/gpg-agent.conf
        echo "default-cache-ttl-ssh 600" >> ~/.gnupg/gpg-agent.conf
        echo "max-cache-ttl-ssh 7200" >> ~/.gnupg/gpg-agent.conf
        echo "Added SSH support to ~/.gnupg/gpg-agent.conf"
    else
        echo "SSH support already configured in gpg-agent.conf"
    fi

    # Create bashrc.d directory and GPG/YubiKey script
    mkdir -p ~/.bashrc.d

    if [[ ! -f ~/.bashrc.d/gpg-yubikey.sh ]]; then
        echo '#!/bin/bash' > ~/.bashrc.d/gpg-yubikey.sh
        echo '# GPG and Yubikey SSH configuration' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '# Set GPG TTY' >> ~/.bashrc.d/gpg-yubikey.sh
        echo 'export GPG_TTY=$(tty)' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '# Use gpg-agent for SSH' >> ~/.bashrc.d/gpg-yubikey.sh
        echo 'export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '# Ensure gpg-agent is running with SSH support' >> ~/.bashrc.d/gpg-yubikey.sh
        echo 'if ! pgrep -x gpg-agent > /dev/null; then' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '    gpg-agent --daemon --enable-ssh-support > /dev/null 2>&1' >> ~/.bashrc.d/gpg-yubikey.sh
        echo 'fi' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '' >> ~/.bashrc.d/gpg-yubikey.sh
        echo '# Update the gpg-agent TTY (for pinentry)' >> ~/.bashrc.d/gpg-yubikey.sh
        echo 'gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1' >> ~/.bashrc.d/gpg-yubikey.sh
        echo "Created ~/.bashrc.d/gpg-yubikey.sh"
    else
        echo "~/.bashrc.d/gpg-yubikey.sh already exists, skipping"
    fi

    # Disable 1Password SSH agent if configured
    if [[ -f ~/.bash_profile ]] && grep -q 'SSH_AUTH_SOCK.*1password' ~/.bash_profile; then
        sed -i 's|^export SSH_AUTH_SOCK=.*1password.*|# Disabled: export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"|' ~/.bash_profile
        echo "Disabled 1Password SSH agent in ~/.bash_profile"
    fi

    if [[ -f ~/.ssh/config ]] && grep -q 'IdentityAgent.*1password' ~/.ssh/config; then
        sed -i 's|^\t*IdentityAgent.*1password|#\tIdentityAgent ~/.1password/agent.sock|' ~/.ssh/config
        echo "Disabled 1Password SSH agent in ~/.ssh/config"
    fi

    # Restart GPG agent
    gpgconf --kill gpg-agent
    gpgconf --kill scdaemon

    echo ""
    echo "${b}YubiKey SSH setup complete!${n}"
    echo ""
    echo "Next steps:"
    echo "  1. Open a new terminal or run: source ~/.bashrc.d/gpg-yubikey.sh"
    echo "  2. Insert your YubiKey"
    echo "  3. Import your GPG public key: gpg --import <your-public-key.asc>"
    echo "  4. Verify with: ssh-add -L"
    echo ""
    echo "Your YubiKey's SSH key will be available after importing the GPG public key."

# Toggle system suspend for remote access
[group('Rocinante')]
toggle-suspend:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    LOGIND_CONFIG="/etc/systemd/logind.conf.d/no-suspend.conf"
    GDM_CONFIG="/etc/dconf/db/gdm.d/99-no-suspend"

    if [[ -f "$LOGIND_CONFIG" ]]; then
        echo "${b}Suspend is currently DISABLED${n}"
        echo ""
        echo "Removing configurations to re-enable suspend..."
        sudo rm -f "$LOGIND_CONFIG"
        sudo rm -f "$GDM_CONFIG"
        sudo dconf update
        sudo systemctl restart systemd-logind
        echo ""
        echo "${b}Suspend is now ENABLED${n}"
        echo "System will suspend normally when idle or lid is closed."
    else
        echo "${b}Suspend is currently ENABLED${n}"
        echo ""
        echo "Configuring logind to prevent suspend..."
        sudo mkdir -p /etc/systemd/logind.conf.d
        echo "[Login]" | sudo tee "$LOGIND_CONFIG" > /dev/null
        echo "# Prevent automatic suspend for remote access" | sudo tee -a "$LOGIND_CONFIG" > /dev/null
        echo "IdleAction=ignore" | sudo tee -a "$LOGIND_CONFIG" > /dev/null
        echo "HandleLidSwitch=ignore" | sudo tee -a "$LOGIND_CONFIG" > /dev/null
        echo "HandleLidSwitchExternalPower=ignore" | sudo tee -a "$LOGIND_CONFIG" > /dev/null

        echo "Configuring GDM to prevent suspend at login screen..."
        sudo mkdir -p /etc/dconf/db/gdm.d
        echo "# Prevent GDM from suspending while waiting for login" | sudo tee "$GDM_CONFIG" > /dev/null
        echo "[org/gnome/settings-daemon/plugins/power]" | sudo tee -a "$GDM_CONFIG" > /dev/null
        echo "sleep-inactive-ac-type='nothing'" | sudo tee -a "$GDM_CONFIG" > /dev/null
        echo "sleep-inactive-battery-type='nothing'" | sudo tee -a "$GDM_CONFIG" > /dev/null
        sudo dconf update

        sudo systemctl restart systemd-logind
        echo ""
        echo "${b}Suspend is now DISABLED${n}"
        echo "System will stay awake for remote access, even at the login screen."
    fi

# Configure 1Password for Flatpak browsers (Firefox, Chrome, Brave, etc.)
[group('Rocinante')]
setup-1password-browser:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    echo "${b}Setting up 1Password Flatpak browser integration...${n}"

    # Detect installed Flatpak browsers
    BROWSERS=()
    for browser in org.mozilla.firefox com.google.Chrome com.brave.Browser org.chromium.Chromium; do
        if flatpak list 2>/dev/null | grep -q "$browser"; then
            BROWSERS+=("$browser")
            echo "Found: $browser"
        fi
    done

    if [[ ${#BROWSERS[@]} -eq 0 ]]; then
        echo "No supported Flatpak browsers found."
        echo "Install a Flatpak browser first (e.g., flatpak install flathub org.mozilla.firefox)"
        exit 0
    fi

    # Clone and run integration script
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    cd "$TEMP_DIR"

    echo "Downloading integration script..."
    if git clone --depth 1 --quiet https://github.com/FlyinPancake/1password-flatpak-browser-integration; then
        cd 1password-flatpak-browser-integration
        for browser in "${BROWSERS[@]}"; do
            echo ""
            echo "Configuring ${b}$browser${n}..."
            echo "$browser" | ./1password-flatpak-browser-integration.sh
        done
        echo ""
        echo "${b}Done!${n}"
        echo "Restart your browser(s) to complete setup."
        echo "Then verify in 1Password: Settings → Browser → check extension is connected."
    else
        echo "Failed to download integration script"
        exit 1
    fi

# Run first-time user setup tasks
[group('Rocinante')]
first-run:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    echo "${b}╔══════════════════════════════════════╗${n}"
    echo "${b}║     Rocinante First-Run Setup        ║${n}"
    echo "${b}╚══════════════════════════════════════╝${n}"
    echo ""

    # 1Password browser integration
    if command -v 1password >/dev/null 2>&1; then
        echo "${b}[1/2] 1Password Browser Integration${n}"
        if flatpak list 2>/dev/null | grep -qE "org.mozilla.firefox|com.google.Chrome|com.brave.Browser"; then
            echo "Flatpak browser detected. Setting up 1Password integration..."
            ujust setup-1password-browser
        else
            echo "No Flatpak browsers found, skipping 1Password browser setup."
        fi
    else
        echo "1Password not found, skipping browser integration."
    fi

    echo ""
    echo "${b}[2/2] Additional Setup${n}"
    echo "Other setup tasks you may want to run:"
    echo "  - ujust setup-yubikey-ssh       # If using YubiKey for SSH"
    echo "  - ujust toggle-suspend          # If using for remote access"
    echo "  - ujust toggle-openvpn-indicator # If using OpenVPN"
    echo ""
    echo "${b}First-run setup complete!${n}"

# Toggle OpenVPN indicator autostart
[group('Rocinante')]
toggle-openvpn-indicator:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    AUTOSTART_SRC="/etc/xdg/autostart/openvpn3-indicator.desktop"
    AUTOSTART_USER="$HOME/.config/autostart/openvpn3-indicator.desktop"

    # Check if system autostart exists
    if [[ ! -f "$AUTOSTART_SRC" ]]; then
        echo "OpenVPN indicator is not installed."
        exit 1
    fi

    # Check current state - user override takes precedence
    if [[ -f "$AUTOSTART_USER" ]]; then
        if grep -q "Hidden=true" "$AUTOSTART_USER" 2>/dev/null; then
            CURRENT_STATE="disabled"
        else
            CURRENT_STATE="enabled"
        fi
    else
        # No user override - check if system default is masked
        if grep -q "Hidden=true" "$AUTOSTART_SRC" 2>/dev/null; then
            CURRENT_STATE="disabled"
        else
            CURRENT_STATE="enabled"
        fi
    fi

    if [[ "$CURRENT_STATE" == "enabled" ]]; then
        echo "${b}OpenVPN indicator is currently ENABLED${n}"
        echo "Disabling autostart..."
        mkdir -p "$HOME/.config/autostart"
        cp "$AUTOSTART_SRC" "$AUTOSTART_USER"
        echo "Hidden=true" >> "$AUTOSTART_USER"
        # Stop the running indicator if any
        pkill -f openvpn3-indicator 2>/dev/null || true
        echo ""
        echo "${b}OpenVPN indicator is now DISABLED${n}"
        echo "It will no longer start automatically on login."
    else
        echo "${b}OpenVPN indicator is currently DISABLED${n}"
        echo "Enabling autostart..."
        # Remove user override to use system default, or create enabled override
        if [[ -f "$AUTOSTART_USER" ]]; then
            rm "$AUTOSTART_USER"
        fi
        # If system default is also disabled, create an enabled user override
        if grep -q "Hidden=true" "$AUTOSTART_SRC" 2>/dev/null; then
            mkdir -p "$HOME/.config/autostart"
            grep -v "Hidden=true" "$AUTOSTART_SRC" > "$AUTOSTART_USER"
        fi
        # Start the indicator now
        nohup openvpn3-indicator >/dev/null 2>&1 &
        echo ""
        echo "${b}OpenVPN indicator is now ENABLED${n}"
        echo "It will start automatically on login."
    fi
