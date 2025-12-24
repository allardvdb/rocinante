# vim: set ft=make :
# Rocinante custom ujust recipes

# Configure YubiKey for SSH and git signing using FIDO2 (works with Bio and 5)
[group('Rocinante')]
setup-yubikey-ssh:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    echo "${b}Setting up YubiKey for SSH/git signing (FIDO2)...${n}"
    echo ""

    # Step 1: Enable systemd ssh-agent
    echo "Enabling systemd ssh-agent..."
    systemctl --user enable --now ssh-agent.socket

    # Step 2: Configure SSH_AUTH_SOCK via environment.d
    mkdir -p ~/.config/environment.d
    if [[ ! -f ~/.config/environment.d/10-ssh-agent.conf ]]; then
        cat > ~/.config/environment.d/10-ssh-agent.conf << 'EOF'
# Use systemd ssh-agent for FIDO2/sk-ssh keys (YubiKey Bio/5)
SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh-agent.socket
EOF
        echo "Created ~/.config/environment.d/10-ssh-agent.conf"
    else
        echo "~/.config/environment.d/10-ssh-agent.conf already exists"
    fi

    # Step 3: Disable GPG agent SSH support if enabled
    if [[ -f ~/.gnupg/gpg-agent.conf ]] && grep -q "^enable-ssh-support" ~/.gnupg/gpg-agent.conf; then
        sed -i 's/^enable-ssh-support/# enable-ssh-support  # Disabled - using systemd ssh-agent for FIDO2/' ~/.gnupg/gpg-agent.conf
        echo "Disabled GPG agent SSH support in ~/.gnupg/gpg-agent.conf"
    fi

    # Step 4: Remove old GPG SSH bashrc script if present
    if [[ -f ~/.bashrc.d/gpg-yubikey.sh ]]; then
        rm ~/.bashrc.d/gpg-yubikey.sh
        echo "Removed old ~/.bashrc.d/gpg-yubikey.sh"
    fi

    # Step 5: Check for existing FIDO2 SSH key
    echo ""
    SK_KEY=""
    if [[ -f ~/.ssh/id_ed25519_sk.pub ]]; then
        SK_KEY=~/.ssh/id_ed25519_sk.pub
        echo "Found existing FIDO2 key: $SK_KEY"
    elif [[ -f ~/.ssh/id_ecdsa_sk.pub ]]; then
        SK_KEY=~/.ssh/id_ecdsa_sk.pub
        echo "Found existing FIDO2 key: $SK_KEY"
    fi

    if [[ -z "$SK_KEY" ]]; then
        echo "${b}No FIDO2 SSH key found.${n}"
        echo ""
        echo "To generate one, insert your YubiKey and run:"
        echo "  ssh-keygen -t ed25519-sk -C \"your-email@example.com\""
        echo ""
        echo "Then re-run this setup."
        exit 0
    fi

    # Step 6: Configure git for SSH signing
    echo ""
    echo "Configuring git for SSH signing..."
    git config --global gpg.format ssh
    git config --global user.signingkey "key::$(cat "$SK_KEY")"
    git config --global commit.gpgsign true

    # Remove 1Password signing program if set
    if git config --global gpg.ssh.program &>/dev/null; then
        git config --global --unset gpg.ssh.program
        echo "Removed 1Password SSH signing program from git config"
    fi

    # Step 7: Add key to current ssh-agent session
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
    SK_PRIVATE="${SK_KEY%.pub}"
    if [[ -f "$SK_PRIVATE" ]]; then
        echo ""
        echo "Adding key to ssh-agent (touch YubiKey when prompted)..."
        ssh-add "$SK_PRIVATE" 2>/dev/null || echo "Key may already be added or YubiKey not present"
    fi

    echo ""
    echo "${b}YubiKey SSH setup complete!${n}"
    echo ""
    echo "Your FIDO2 key: $(cat "$SK_KEY")"
    echo ""
    echo "${b}Next steps:${n}"
    echo "  1. Log out and back in (or export SSH_AUTH_SOCK=\"\${XDG_RUNTIME_DIR}/ssh-agent.socket\")"
    echo "  2. Add your public key to GitHub as a ${b}Signing Key${n}:"
    echo "     GitHub → Settings → SSH and GPG keys → New SSH key → Key type: Signing Key"
    echo "  3. Test: git commit -S -m \"test\" (touch YubiKey when it blinks)"
    echo ""
    echo "For GPG operations with YubiKey 5, use: ujust enable-yubikey-gpg"

# Prepare current shell for GPG operations with YubiKey 5
[group('Rocinante')]
enable-yubikey-gpg:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh

    echo "${b}Enabling GPG/YubiKey for this shell session...${n}"
    echo ""

    # Configure scdaemon if needed
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg

    if [[ ! -f ~/.gnupg/scdaemon.conf ]]; then
        cat > ~/.gnupg/scdaemon.conf << 'EOF'
# Disable scdaemon's built-in CCID driver to prevent conflict with pcscd
disable-ccid
# Allow shared access to the card
pcsc-shared
EOF
        echo "Created ~/.gnupg/scdaemon.conf"
    fi

    # Kill existing scdaemon to pick up config
    gpgconf --kill scdaemon 2>/dev/null || true

    echo ""
    echo "Run these commands in your current shell:"
    echo ""
    echo "  export GPG_TTY=\$(tty)"
    echo "  export SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket)"
    echo "  gpg-connect-agent updatestartuptty /bye"
    echo ""
    echo "Or copy-paste this one-liner:"
    echo ""
    echo "  ${b}export GPG_TTY=\$(tty) SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket); gpg-connect-agent updatestartuptty /bye${n}"
    echo ""
    echo "Then verify your YubiKey:"
    echo "  gpg --card-status"
    echo "  ssh-add -L"

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
