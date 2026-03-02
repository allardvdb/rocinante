# vim: set ft=make :
# Rocinante custom ujust recipes

# Configure YubiKey for SSH and git signing using FIDO2 (works with Bio and 5)
[group('Rocinante')]
setup-yubikey-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""

    echo "${b}Setting up YubiKey for SSH/git signing (FIDO2)...${n}"
    echo ""

    # Step 1: Enable systemd ssh-agent
    echo "Enabling systemd ssh-agent..."
    systemctl --user enable --now ssh-agent.socket

    # Step 2: Configure SSH_AUTH_SOCK via environment.d
    mkdir -p ~/.config/environment.d
    if [[ ! -f ~/.config/environment.d/10-ssh-agent.conf ]]; then
        echo "# Use systemd ssh-agent for FIDO2/sk-ssh keys (YubiKey Bio/5)" > ~/.config/environment.d/10-ssh-agent.conf
        echo 'SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh-agent.socket' >> ~/.config/environment.d/10-ssh-agent.conf
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
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""

    echo "${b}Enabling GPG/YubiKey for this shell session...${n}"
    echo ""

    # Configure scdaemon if needed
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg

    if [[ ! -f ~/.gnupg/scdaemon.conf ]]; then
        echo "# Disable scdaemon's built-in CCID driver to prevent conflict with pcscd" > ~/.gnupg/scdaemon.conf
        echo "disable-ccid" >> ~/.gnupg/scdaemon.conf
        echo "# Allow shared access to the card" >> ~/.gnupg/scdaemon.conf
        echo "pcsc-shared" >> ~/.gnupg/scdaemon.conf
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
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""

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
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""

    echo "${b}Setting up 1Password Flatpak browser integration...${n}"
    echo ""

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

    # Check if Firefox has been run at least once
    FIREFOX_NEEDS_INIT=false
    if [[ " ${BROWSERS[@]} " =~ " org.mozilla.firefox " ]]; then
        if [[ ! -d "$HOME/.var/app/org.mozilla.firefox/.mozilla" ]]; then
            echo ""
            echo "${yellow}${b}Firefox has not been initialized yet.${n}"
            read -p "Initialize Firefox profile now? [Y/n]: " init_confirm
            if [[ ! "$init_confirm" =~ ^[Nn]$ ]]; then
                echo "Initializing Firefox profile (this takes a few seconds)..."
                timeout 10 flatpak run org.mozilla.firefox --headless 2>/dev/null || true
                sleep 2
                if [[ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla" ]]; then
                    echo "Firefox profile initialized successfully"
                    FIREFOX_NEEDS_INIT=true
                else
                    echo "${yellow}Failed to initialize Firefox profile automatically.${n}"
                    echo "Please run Firefox manually first: ${b}flatpak run org.mozilla.firefox${n}"
                    exit 1
                fi
            else
                echo "Please initialize Firefox manually first: ${b}flatpak run org.mozilla.firefox${n}"
                exit 0
            fi
        fi
    fi

    # Clone and run integration script
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    cd "$TEMP_DIR"

    echo ""
    echo "Downloading integration script..."
    if git clone --depth 1 --quiet --branch fix-xdg-firefox-path https://github.com/allardvdb/1password-flatpak-browser-integration; then
        cd 1password-flatpak-browser-integration
        for browser in "${BROWSERS[@]}"; do
            echo ""
            echo "Configuring ${b}$browser${n}..."
            echo "$browser" | ./1password-flatpak-browser-integration.sh
        done

        # Fix Firefox Flatpak native-messaging-hosts path
        # Firefox Flatpak looks in ~/.mozilla/native-messaging-hosts, not config/mozilla/native-messaging-hosts
        if [[ " ${BROWSERS[@]} " =~ " org.mozilla.firefox " ]]; then
            FIREFOX_MOZILLA_PATH="$HOME/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts"
            FIREFOX_CONFIG_PATH="$HOME/.var/app/org.mozilla.firefox/config/mozilla/native-messaging-hosts"
            if [[ -f "$FIREFOX_CONFIG_PATH/com.1password.1password.json" ]]; then
                echo ""
                echo "Moving Firefox native-messaging config to correct location..."
                mkdir -p "$FIREFOX_MOZILLA_PATH"
                cp "$FIREFOX_CONFIG_PATH/com.1password.1password.json" "$FIREFOX_MOZILLA_PATH/"
                echo "Fixed Firefox Flatpak path"
            fi
        fi

        echo ""
        echo "${b}Setup complete!${n}"
        echo ""

        # Offer to open Firefox to install extension
        if [[ " ${BROWSERS[@]} " =~ " org.mozilla.firefox " ]]; then
            echo "${b}Next step: Install the 1Password browser extension${n}"
            echo ""
            read -p "Open Firefox to install the 1Password extension now? [Y/n]: " open_confirm
            if [[ ! "$open_confirm" =~ ^[Nn]$ ]]; then
                echo "Opening Firefox to 1Password extension page..."
                flatpak run org.mozilla.firefox "https://addons.mozilla.org/firefox/addon/1password-x-password-manager/" &
                sleep 2
                echo ""
                echo "${b}In Firefox:${n}"
                echo "  1. Click 'Add to Firefox' and confirm the installation"
                echo "  2. Click the 1Password extension icon in the toolbar"
                echo "  3. Go to Settings (⚙️) → General"
                echo "  4. Enable 'Integrate this extension with the 1Password desktop app'"
                echo "  5. Verify: Integration status should show 'Connected' ✓"
            else
                echo ""
                echo "${b}Manual installation:${n}"
                echo "  1. Open Firefox and go to:"
                echo "     https://addons.mozilla.org/firefox/addon/1password-x-password-manager/"
                echo ""
                echo "  2. Click 'Add to Firefox' and confirm"
                echo ""
                echo "  3. Open 1Password extension settings and enable desktop app integration"
                echo ""
                echo "  4. Verify: Settings → Browser → Integration status should show 'Connected'"
            fi
        else
            echo "${b}Next steps:${n}"
            echo "  1. Install the 1Password browser extension:"
            echo "     Chrome: https://chrome.google.com/webstore/detail/1password/aeblfdkhhhdcdjpifhhbdiojplfjncoa"
            echo ""
            echo "  2. Open 1Password extension settings and enable desktop app integration"
            echo ""
            echo "  3. Verify: Settings → Browser → Integration status should show 'Connected'"
        fi
    else
        echo "Failed to download integration script"
        exit 1
    fi

# Run first-time user setup tasks
[group('Rocinante')]
first-run:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""

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
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""

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

# Configure YubiKey for PAM authentication (sudo, polkit, screen unlock)
[group('Rocinante')]
configure-yubikey-pam ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    red=$(tput setaf 1 2>/dev/null) || red=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    cyan=$(tput setaf 6 2>/dev/null) || cyan=""

    U2F_KEYS="$HOME/.config/Yubico/u2f_keys"
    HOSTNAME=$(hostname)

    # Check prerequisites
    if ! command -v pamu2fcfg &> /dev/null; then
        echo "${red}${b}Error:${n} pam-u2f is not installed."
        echo ""
        echo "This package should be included in the rocinante image."
        echo "If testing locally, install with: ${b}sudo dnf install pam-u2f${n}"
        exit 1
    fi

    # Check for YubiKey
    if ! lsusb | grep -qi yubi; then
        echo "${red}${b}Error:${n} No YubiKey detected. Please insert your YubiKey."
        exit 1
    fi

    # Action selection
    ACTION_ARG="{{ ACTION }}"
    if [[ -z "$ACTION_ARG" ]]; then
        echo "${b}YubiKey PAM Configuration${n}"
        echo ""
        if command -v gum &> /dev/null; then
            ACTION=$(gum choose \
                "Setup PAM authentication" \
                "Register additional key" \
                "Show current configuration" \
                "Remove configuration")
        else
            echo "Select an action:"
            echo "  1) Setup PAM authentication"
            echo "  2) Register additional key"
            echo "  3) Show current configuration"
            echo "  4) Remove configuration"
            echo ""
            read -p "Choice [1-4]: " choice
            case "$choice" in
                1) ACTION="Setup PAM authentication" ;;
                2) ACTION="Register additional key" ;;
                3) ACTION="Show current configuration" ;;
                4) ACTION="Remove configuration" ;;
                *) echo "Invalid choice"; exit 1 ;;
            esac
        fi
    else
        ACTION="$ACTION_ARG"
    fi

    case "$ACTION" in
        "Setup PAM authentication"|"setup")
            # Setup PAM authentication
            echo ""
            echo "${b}YubiKey PAM Setup${n}"
            echo "================="
            echo ""

            # Check if already configured
            if [[ -f "$U2F_KEYS" ]]; then
                echo "${yellow}${b}Warning:${n} u2f_keys already exists at $U2F_KEYS"
                echo ""
                read -p "Overwrite existing configuration? [y/N]: " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    echo "Cancelled. Use 'Register additional key' to add more keys."
                    exit 0
                fi
            fi

            # Create directory
            mkdir -p "$(dirname "$U2F_KEYS")"

            echo "${cyan}Step 1: Register primary YubiKey${n}"
            echo "Touch your YubiKey when it blinks..."
            echo ""

            if pamu2fcfg -o "pam://$HOSTNAME" -i "pam://$HOSTNAME" > "$U2F_KEYS"; then
                echo "${green}${b}✓${n} Primary key registered"
            else
                echo "${red}${b}Error:${n} Failed to register YubiKey"
                exit 1
            fi

            # Backup key
            echo ""
            read -p "Register a backup YubiKey? (recommended) [y/N]: " backup_confirm
            if [[ "$backup_confirm" =~ ^[Yy]$ ]]; then
                echo ""
                echo "Remove primary YubiKey and insert backup key..."
                read -p "Press Enter when ready..."

                echo "Touch your backup YubiKey when it blinks..."
                if pamu2fcfg -o "pam://$HOSTNAME" -i "pam://$HOSTNAME" -n >> "$U2F_KEYS"; then
                    echo "${green}${b}✓${n} Backup key registered"
                else
                    echo "${yellow}${b}Warning:${n} Failed to register backup key (continuing anyway)"
                fi
            fi

            # authselect configuration
            echo ""
            echo "${cyan}Step 2: Configure authselect${n}"
            echo ""

            CURRENT_PROFILE=$(authselect current 2>/dev/null | head -1 || echo "")
            echo "Current profile: ${CURRENT_PROFILE:-none}"

            if echo "$CURRENT_PROFILE" | grep -q "with-pam-u2f"; then
                echo "${green}${b}✓${n} PAM U2F already enabled in authselect"
            else
                echo ""
                echo "This will enable YubiKey authentication for:"
                echo "  - sudo"
                echo "  - 1Password / polkit prompts"
                echo "  - Other system-auth consumers"
                echo ""

                read -p "Enable authselect with-pam-u2f? [Y/n]: " auth_confirm
                if [[ ! "$auth_confirm" =~ ^[Nn]$ ]]; then
                    if sudo authselect select sssd with-pam-u2f --force; then
                        echo "${green}${b}✓${n} authselect configured"
                    else
                        echo "${red}${b}Error:${n} Failed to configure authselect"
                        exit 1
                    fi
                fi
            fi

            # Screen unlock option
            echo ""
            echo "${cyan}Step 3: Screen unlock configuration (optional)${n}"
            echo ""
            echo "By default, GDM boot login uses password (to unlock keyring)."
            echo "Screen unlock can use YubiKey via gdm-fingerprint."
            echo ""

            read -p "Configure YubiKey for screen unlock? [y/N]: " unlock_confirm
            if [[ "$unlock_confirm" =~ ^[Yy]$ ]]; then
                GDM_FP="/etc/pam.d/gdm-fingerprint"
                if [[ -f "$GDM_FP" ]]; then
                    if grep -q "pam_u2f.so" "$GDM_FP"; then
                        echo "${green}${b}✓${n} Already configured in gdm-fingerprint"
                    else
                        echo "Adding pam_u2f to gdm-fingerprint..."
                        sudo sed -i '1a auth     sufficient pam_u2f.so cue' "$GDM_FP"
                        echo "${green}${b}✓${n} gdm-fingerprint configured"
                    fi
                else
                    echo "${yellow}${b}Warning:${n} gdm-fingerprint not found (may not be applicable)"
                fi
            fi

            # Verification
            echo ""
            echo "${cyan}Step 4: Verification${n}"
            echo ""
            echo "Testing sudo with YubiKey..."
            echo "Touch your YubiKey when prompted..."
            echo ""

            if sudo -k && sudo echo "${green}${b}✓ YubiKey sudo works!${n}"; then
                echo ""
                echo "${green}${b}Setup complete!${n}"
                echo ""
                echo "Summary:"
                echo "  - u2f_keys: $U2F_KEYS"
                echo "  - authselect: with-pam-u2f enabled"
                echo "  - YubiKey OR password accepted for sudo/polkit"
            else
                echo "${yellow}${b}Warning:${n} sudo test failed or cancelled"
                echo "You can still authenticate with password as fallback."
            fi
            ;;

        "Register additional key"|"register")
            # Register additional key
            echo ""
            if [[ ! -f "$U2F_KEYS" ]]; then
                echo "${red}${b}Error:${n} No existing u2f_keys found."
                echo "Run 'Setup PAM authentication' first."
                exit 1
            fi

            KEY_COUNT=$(wc -l < "$U2F_KEYS")
            echo "Current registered keys: $KEY_COUNT"
            echo ""

            echo "Insert the YubiKey you want to register..."
            echo "Touch it when it blinks..."
            echo ""

            if pamu2fcfg -o "pam://$HOSTNAME" -i "pam://$HOSTNAME" -n >> "$U2F_KEYS"; then
                NEW_COUNT=$(wc -l < "$U2F_KEYS")
                echo "${green}${b}✓${n} Additional key registered"
                echo "  $NEW_COUNT key(s) now registered"
            else
                echo "${red}${b}Error:${n} Failed to register key"
                exit 1
            fi
            ;;

        "Show current configuration"|"show")
            # Show configuration
            echo ""
            echo "${b}YubiKey PAM Configuration${n}"
            echo "========================="
            echo ""

            # u2f_keys status
            echo "${cyan}u2f_keys:${n}"
            if [[ -f "$U2F_KEYS" ]]; then
                KEY_COUNT=$(wc -l < "$U2F_KEYS")
                echo "  Location: $U2F_KEYS"
                echo "  Keys registered: $KEY_COUNT"
                echo "  Origin/AppID: pam://$HOSTNAME"
            else
                echo "  ${yellow}Not configured${n}"
            fi
            echo ""

            # authselect status
            echo "${cyan}authselect:${n}"
            if command -v authselect &> /dev/null; then
                authselect current 2>/dev/null | sed 's/^/  /' || echo "  Not configured"
            else
                echo "  authselect not available"
            fi
            echo ""

            # gdm-fingerprint status
            echo "${cyan}gdm-fingerprint (screen unlock):${n}"
            if [[ -f /etc/pam.d/gdm-fingerprint ]]; then
                if grep -q "pam_u2f.so" /etc/pam.d/gdm-fingerprint; then
                    echo "  ${green}YubiKey enabled${n}"
                else
                    echo "  ${yellow}YubiKey not configured${n} (password only)"
                fi
            else
                echo "  Not applicable (file not found)"
            fi
            echo ""

            # YubiKey detection
            echo "${cyan}Connected YubiKey:${n}"
            if command -v ykman &> /dev/null; then
                ykman info 2>/dev/null | head -5 | sed 's/^/  /' || echo "  No YubiKey detected"
            else
                if lsusb | grep -qi yubi; then
                    lsusb | grep -i yubi | sed 's/^/  /'
                else
                    echo "  No YubiKey detected"
                fi
            fi
            ;;

        "Remove configuration"|"remove")
            # Remove configuration
            echo ""
            echo "${yellow}${b}Warning:${n} This will remove YubiKey PAM authentication."
            echo "You will need to use password for sudo/polkit."
            echo ""

            read -p "Remove YubiKey PAM configuration? [y/N]: " remove_confirm
            if [[ ! "$remove_confirm" =~ ^[Yy]$ ]]; then
                exit 0
            fi

            # Remove u2f_keys
            if [[ -f "$U2F_KEYS" ]]; then
                rm -f "$U2F_KEYS"
                echo "${green}${b}✓${n} Removed $U2F_KEYS"
            fi

            # Remove from authselect
            CURRENT=$(authselect current 2>/dev/null || echo "")
            if echo "$CURRENT" | grep -q "with-pam-u2f"; then
                echo "Removing with-pam-u2f from authselect..."
                sudo authselect select sssd --force
                echo "${green}${b}✓${n} authselect reset to sssd (no pam-u2f)"
            fi

            # Remove from gdm-fingerprint
            if [[ -f /etc/pam.d/gdm-fingerprint ]] && grep -q "pam_u2f.so" /etc/pam.d/gdm-fingerprint; then
                sudo sed -i '/pam_u2f.so/d' /etc/pam.d/gdm-fingerprint
                echo "${green}${b}✓${n} Removed pam_u2f from gdm-fingerprint"
            fi

            echo ""
            echo "${green}${b}Configuration removed${n}"
            echo "Password authentication is now required for sudo/polkit."
            ;;

        *)
            echo "Unknown action: $ACTION"
            echo "Valid actions: setup, register, show, remove"
            exit 1
            ;;
    esac
