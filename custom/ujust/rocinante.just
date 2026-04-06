# Rocinante custom ujust recipes

# Switch between release streams (stable, testing, latest)
[group('Rocinante')]
switch-stream:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""

    # Detect current image and tag from bootc status
    BOOTC_JSON=$(bootc status --json 2>/dev/null)
    CURRENT_IMAGE=$(echo "$BOOTC_JSON" | jq -r '.spec.image.image // empty')
    if [[ -z "$CURRENT_IMAGE" ]]; then
        echo "Error: Could not detect current image from bootc status"
        exit 1
    fi

    # Split into base and tag
    IMAGE_BASE="${CURRENT_IMAGE%%:*}"
    CURRENT_TAG="${CURRENT_IMAGE##*:}"
    if [[ "$CURRENT_TAG" == "$CURRENT_IMAGE" ]]; then
        CURRENT_TAG="latest"
    fi

    # Determine current stream from tag
    CURRENT_STREAM="$CURRENT_TAG"
    # Strip date suffix if present (e.g., stable.20260311 → stable)
    CURRENT_STREAM="${CURRENT_STREAM%%.*}"

    echo "${b}Release Stream Switcher${n}"
    echo ""
    echo "  Image:   ${IMAGE_BASE}"
    echo "  Current: ${CURRENT_TAG} (stream: ${CURRENT_STREAM})"
    echo ""

    # Present stream menu
    STREAMS=("stable" "testing" "latest")
    if command -v gum &> /dev/null; then
        SELECTED=$(gum choose --header "Select stream:" "${STREAMS[@]}")
    else
        echo "Select stream:"
        echo "  1) stable   — Daily drivers, manually promoted"
        echo "  2) testing  — Pre-release soak"
        echo "  3) latest   — Bleeding edge, every build"
        echo ""
        read -p "Choice [1-3]: " choice
        case "$choice" in
            1) SELECTED="stable" ;;
            2) SELECTED="testing" ;;
            3) SELECTED="latest" ;;
            *) echo "Invalid choice"; exit 1 ;;
        esac
    fi

    if [[ -z "$SELECTED" ]]; then
        exit 0
    fi

    # No-op guard
    if [[ "$CURRENT_STREAM" == "$SELECTED" ]]; then
        echo ""
        echo "${green}Already on the ${b}${SELECTED}${n}${green} stream — nothing to do.${n}"
        exit 0
    fi

    TARGET="${IMAGE_BASE}:${SELECTED}"
    echo ""
    echo "Switching: ${CURRENT_TAG} → ${b}${SELECTED}${n}"
    echo "  ${TARGET}"
    echo ""
    read -p "Continue? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    sudo bootc switch "${TARGET}" --enforce-container-sigpolicy

    echo ""
    echo "${green}${b}Switched to ${SELECTED} stream.${n}"
    echo "Reboot to apply: ${b}systemctl reboot${n}"

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

    # Detect desktop environment
    IS_GNOME=false
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
        IS_GNOME=true
    fi

    LOGIND_CONFIG="/etc/systemd/logind.conf.d/no-suspend.conf"
    GDM_CONFIG="/etc/dconf/db/gdm.d/99-no-suspend"

    if [[ -f "$LOGIND_CONFIG" ]]; then
        echo "${b}Suspend is currently DISABLED${n}"
        echo ""
        echo "Removing configurations to re-enable suspend..."
        sudo rm -f "$LOGIND_CONFIG"
        if [[ "$IS_GNOME" == true ]]; then
            sudo rm -f "$GDM_CONFIG"
            sudo dconf update
        fi
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

        if [[ "$IS_GNOME" == true ]]; then
            echo "Configuring GDM to prevent suspend at login screen..."
            sudo mkdir -p /etc/dconf/db/gdm.d
            echo "# Prevent GDM from suspending while waiting for login" | sudo tee "$GDM_CONFIG" > /dev/null
            echo "[org/gnome/settings-daemon/plugins/power]" | sudo tee -a "$GDM_CONFIG" > /dev/null
            echo "sleep-inactive-ac-type='nothing'" | sudo tee -a "$GDM_CONFIG" > /dev/null
            echo "sleep-inactive-battery-type='nothing'" | sudo tee -a "$GDM_CONFIG" > /dev/null
            sudo dconf update
        else
            echo ""
            echo "${b}Note:${n} GDM login screen suspend config skipped (not GNOME)."
            echo "To prevent SDDM from suspending, configure via:"
            echo "  ${b}System Settings → Energy Saving${n}"
        fi

        sudo systemctl restart systemd-logind
        echo ""
        echo "${b}Suspend is now DISABLED${n}"
        echo "System will stay awake for remote access."
        if [[ "$IS_GNOME" != true ]]; then
            echo "${b}Note:${n} Login screen suspend must be configured separately in System Settings."
        fi
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

# Configure IOMMU and Incus for GPU passthrough
[group('Rocinante')]
setup-gpu-passthrough:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    red=$(tput setaf 1 2>/dev/null) || red=""

    echo "${b}GPU Passthrough Setup (IOMMU + Incus)${n}"
    echo ""

    # Step 1: Detect CPU vendor and determine IOMMU parameter
    VENDOR=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')
    case "$VENDOR" in
        AuthenticAMD)
            IOMMU_PARAM="amd_iommu=on"
            echo "Detected AMD CPU — will use ${b}${IOMMU_PARAM}${n}"
            ;;
        GenuineIntel)
            IOMMU_PARAM="intel_iommu=on"
            echo "Detected Intel CPU — will use ${b}${IOMMU_PARAM}${n}"
            ;;
        *)
            echo "${red}${b}Error:${n} Unknown CPU vendor: $VENDOR"
            exit 1
            ;;
    esac
    echo ""

    # Step 2: Check current kernel args
    CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
    NEEDS_REBOOT=false

    if echo "$CURRENT_KARGS" | grep -q "$IOMMU_PARAM"; then
        echo "${green}${b}✓${n} ${IOMMU_PARAM} already set in kernel parameters"
    else
        echo "Adding ${b}${IOMMU_PARAM}${n} to kernel boot parameters..."
        sudo rpm-ostree kargs --append-if-missing="$IOMMU_PARAM"
        NEEDS_REBOOT=true
        echo "${green}${b}✓${n} Added ${IOMMU_PARAM}"
    fi

    if echo "$CURRENT_KARGS" | grep -q "iommu=pt"; then
        echo "${green}${b}✓${n} iommu=pt already set in kernel parameters"
    else
        echo "Adding ${b}iommu=pt${n} to kernel boot parameters..."
        sudo rpm-ostree kargs --append-if-missing="iommu=pt"
        NEEDS_REBOOT=true
        echo "${green}${b}✓${n} Added iommu=pt"
    fi
    echo ""

    # Step 3: Add user to incus-admin group
    CURRENT_USER=$(whoami)
    if id -nG "$CURRENT_USER" | grep -qw incus-admin; then
        echo "${green}${b}✓${n} $CURRENT_USER is already in the incus-admin group"
    else
        echo "Adding ${b}${CURRENT_USER}${n} to incus-admin group..."
        sudo usermod -aG incus-admin "$CURRENT_USER"
        NEEDS_REBOOT=true
        echo "${green}${b}✓${n} Added $CURRENT_USER to incus-admin group"
    fi

    if id -nG "$CURRENT_USER" | grep -qw incus; then
        echo "${green}${b}✓${n} $CURRENT_USER is already in the incus group"
    else
        echo "Adding ${b}${CURRENT_USER}${n} to incus group..."
        sudo usermod -aG incus "$CURRENT_USER"
        NEEDS_REBOOT=true
        echo "${green}${b}✓${n} Added $CURRENT_USER to incus group"
    fi
    echo ""

    # Step 4: Verify IOMMU status (if already enabled)
    if [[ -d /sys/kernel/iommu_groups ]] && [[ $(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l) -gt 0 ]]; then
        IOMMU_GROUPS=$(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 -type d | wc -l)
        echo "${green}${b}✓${n} IOMMU is active with $IOMMU_GROUPS groups"
    else
        if [[ "$NEEDS_REBOOT" == true ]]; then
            echo "${yellow}IOMMU groups will be available after reboot${n}"
        else
            echo "${yellow}${b}Warning:${n} No IOMMU groups found. Check BIOS/UEFI settings:"
            echo "  - AMD: Enable IOMMU / SVM"
            echo "  - Intel: Enable VT-d"
        fi
    fi
    echo ""

    # Step 5: Summary and reboot prompt
    echo "${b}Setup complete!${n}"
    echo ""
    if [[ "$NEEDS_REBOOT" == true ]]; then
        echo "${yellow}A reboot is required for changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    else
        echo "No changes needed — everything is already configured."
    fi

# Manage sleep/suspend fixes on Framework 13 AMD (S0ix deep sleep)
[group('Rocinante')]
fix-sleep:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""

    SLEEP_HOOK="/etc/systemd/system-sleep/50-disable-wakeup-sources.sh"
    ASPM_VALUES=("default" "performance" "powersave" "powersupersave")
    KARGS_CHANGED=false

    show_status() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")

        echo "${b}Sleep/Suspend Fixes (Framework 13 AMD)${n}"
        echo ""

        # RTC ACPI alarm
        if echo "$CURRENT_KARGS" | grep -q "rtc_cmos.use_acpi_alarm=1"; then
            echo "  RTC ACPI alarm:      ${green}${b}✓${n} applied"
        else
            echo "  RTC ACPI alarm:      · not applied"
        fi

        # PCIe ASPM policy
        ASPM_CURRENT=""
        for val in "${ASPM_VALUES[@]}"; do
            if echo "$CURRENT_KARGS" | grep -q "pcie_aspm.policy=${val}"; then
                ASPM_CURRENT="$val"
                break
            fi
        done
        if [[ -n "$ASPM_CURRENT" ]]; then
            echo "  PCIe ASPM policy:    ${green}${b}✓${n} ${ASPM_CURRENT}"
        else
            echo "  PCIe ASPM policy:    · unset (kernel default)"
        fi

        # Wakeup source hook
        if [[ -f "$SLEEP_HOOK" ]]; then
            echo "  Wakeup source hook:  ${green}${b}✓${n} installed"
        else
            echo "  Wakeup source hook:  · not installed"
        fi

        # Hibernate status
        if [[ -f /etc/systemd/sleep.conf.d/hibernate.conf ]]; then
            HDELAY=$(grep "HibernateDelaySec" /etc/systemd/sleep.conf.d/hibernate.conf 2>/dev/null | cut -d= -f2 || echo "?")
            echo "  Hibernate delay:     ${green}${b}✓${n} ${HDELAY}"
        else
            echo "  Hibernate delay:     · not configured"
        fi
        echo ""
    }

    choose_menu() {
        local prompt="$1"
        shift
        local options=("$@")
        if command -v gum &> /dev/null; then
            gum choose --header "$prompt" "${options[@]}"
        else
            echo "$prompt" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  ${i}) ${opt}" >&2
                ((i++))
            done
            echo "" >&2
            read -p "Choice [1-${#options[@]}]: " choice
            if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
                echo "${options[$((choice-1))]}"
            else
                echo ""
            fi
        fi
    }

    toggle_rtc() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        if echo "$CURRENT_KARGS" | grep -q "rtc_cmos.use_acpi_alarm=1"; then
            echo "Removing ${b}rtc_cmos.use_acpi_alarm=1${n}..."
            sudo rpm-ostree kargs --delete-if-present="rtc_cmos.use_acpi_alarm=1"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed rtc_cmos.use_acpi_alarm=1"
        else
            echo "Adding ${b}rtc_cmos.use_acpi_alarm=1${n}..."
            sudo rpm-ostree kargs --append-if-missing="rtc_cmos.use_acpi_alarm=1"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Added rtc_cmos.use_acpi_alarm=1"
        fi
    }

    change_aspm() {
        # Detect current value
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        ASPM_CURRENT=""
        for val in "${ASPM_VALUES[@]}"; do
            if echo "$CURRENT_KARGS" | grep -q "pcie_aspm.policy=${val}"; then
                ASPM_CURRENT="$val"
                break
            fi
        done

        local header="PCIe ASPM policy"
        if [[ -n "$ASPM_CURRENT" ]]; then
            header="PCIe ASPM policy (current: ${ASPM_CURRENT})"
        else
            header="PCIe ASPM policy (current: unset)"
        fi

        ACTION=$(choose_menu "$header" "default" "performance" "powersave" "powersupersave" "unset (kernel default)" "Back")

        if [[ "$ACTION" == "Back" || -z "$ACTION" ]]; then
            return
        fi

        # Remove any existing ASPM policy values
        for val in "${ASPM_VALUES[@]}"; do
            sudo rpm-ostree kargs --delete-if-present="pcie_aspm.policy=${val}" 2>/dev/null || true
        done

        if [[ "$ACTION" == "unset (kernel default)" ]]; then
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed PCIe ASPM policy (using kernel default)"
        else
            sudo rpm-ostree kargs --append-if-missing="pcie_aspm.policy=${ACTION}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Set PCIe ASPM policy to ${ACTION}"
        fi
    }

    toggle_wakeup_hook() {
        if [[ -f "$SLEEP_HOOK" ]]; then
            echo "Removing wakeup source hook..."
            sudo rm "$SLEEP_HOOK"
            echo "${green}${b}✓${n} Removed $SLEEP_HOOK"
        else
            echo "Installing wakeup source hook..."
            sudo mkdir -p "$(dirname "$SLEEP_HOOK")"
            sudo tee "$SLEEP_HOOK" > /dev/null << 'HOOK'
    #!/usr/bin/bash
    # Disable touchpad and lid as wakeup sources before suspend
    # These devices generate spurious wakeup events that block S0ix deep sleep
    # on Framework 13 AMD (Strix Point)

    case "$1" in
        pre)
            # Disable touchpad (PIXA3854) wakeup
            for dev in $(find /sys/devices -name "wakeup" -path "*PIXA3854*" 2>/dev/null); do
                echo "disabled" > "$dev" 2>/dev/null || true
            done
            # Disable lid sensor wakeup
            for dev in $(find /sys/devices -name "wakeup" -path "*PNP0C0D*" 2>/dev/null); do
                echo "disabled" > "$dev" 2>/dev/null || true
            done
            ;;
    esac
    HOOK
            sudo chmod 755 "$SLEEP_HOOK"
            echo "${green}${b}✓${n} Installed $SLEEP_HOOK"
        fi
    }

    change_hibernate_delay() {
        local HIBERNATE_CONF="/etc/systemd/sleep.conf.d/hibernate.conf"
        if [[ ! -f "$HIBERNATE_CONF" ]]; then
            echo "${yellow}Hibernate is not configured. Run ${b}ujust setup-hibernate${n}${yellow} first.${n}"
            return
        fi

        CURRENT_DELAY=$(grep "HibernateDelaySec" "$HIBERNATE_CONF" 2>/dev/null | cut -d= -f2 || echo "unknown")
        echo "Current hibernate delay: ${b}${CURRENT_DELAY}${n}"
        echo ""

        DELAY=$(choose_menu "Select hibernate delay:" \
            "15min" "30min" "1h" "2h" "3h")

        if [[ -z "$DELAY" ]]; then
            return
        fi

        sudo tee "$HIBERNATE_CONF" > /dev/null << DELAYEOF
    [Sleep]
    AllowSuspendThenHibernate=yes
    HibernateDelaySec=${DELAY}
    DELAYEOF
        echo "${green}${b}✓${n} Hibernate delay set to ${DELAY}"
        echo "  Takes effect on next suspend (no reboot needed)"
    }

    # Main menu loop
    while true; do
        show_status

        ACTION=$(choose_menu "Select an option:" \
            "Toggle RTC ACPI alarm" \
            "Change PCIe ASPM policy" \
            "Toggle wakeup source hook" \
            "Change hibernate delay" \
            "Done")

        case "$ACTION" in
            "Toggle RTC ACPI alarm") toggle_rtc ;;
            "Change PCIe ASPM policy") change_aspm ;;
            "Toggle wakeup source hook") toggle_wakeup_hook ;;
            "Change hibernate delay") change_hibernate_delay ;;
            "Done"|"") break ;;
        esac
        echo ""
    done

    if [[ "$KARGS_CHANGED" == true ]]; then
        echo "${yellow}A reboot is required for kernel parameter changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    fi

# Manage AMD GPU workarounds for Framework laptops (ring buffer crash fix)
[group('Rocinante')]
fix-amdgpu:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""

    KARGS_CHANGED=false

    show_status() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")

        echo "${b}AMD GPU Fixes (Framework / Ryzen APU)${n}"
        echo ""

        if echo "$CURRENT_KARGS" | grep -q "amdgpu.dcdebugmask=0x10"; then
            echo "  PSR disable:              ${green}${b}✓${n} applied (dcdebugmask=0x10)"
        else
            echo "  PSR disable:              · not applied"
        fi

        if echo "$CURRENT_KARGS" | grep -q "amdgpu.sg_display=0"; then
            echo "  Scatter/gather disable:   ${green}${b}✓${n} applied (sg_display=0)"
        else
            echo "  Scatter/gather disable:   · not applied"
        fi
        echo ""
    }

    choose_menu() {
        local prompt="$1"
        shift
        local options=("$@")
        if command -v gum &> /dev/null; then
            gum choose --header "$prompt" "${options[@]}"
        else
            echo "$prompt" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  ${i}) ${opt}" >&2
                ((i++))
            done
            echo "" >&2
            read -p "Choice [1-${#options[@]}]: " choice
            if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
                echo "${options[$((choice-1))]}"
            else
                echo ""
            fi
        fi
    }

    toggle_karg() {
        local param="$1"
        local label="$2"
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        if echo "$CURRENT_KARGS" | grep -q "${param}"; then
            echo "Removing ${b}${param}${n}..."
            sudo rpm-ostree kargs --delete-if-present="${param}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed ${label}"
        else
            echo "Adding ${b}${param}${n}..."
            sudo rpm-ostree kargs --append-if-missing="${param}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Added ${label}"
        fi
    }

    # Main menu loop
    while true; do
        show_status

        ACTION=$(choose_menu "Select an option:" \
            "Toggle PSR disable (dcdebugmask)" \
            "Toggle scatter/gather disable" \
            "Done")

        case "$ACTION" in
            "Toggle PSR disable (dcdebugmask)") toggle_karg "amdgpu.dcdebugmask=0x10" "PSR disable" ;;
            "Toggle scatter/gather disable") toggle_karg "amdgpu.sg_display=0" "scatter/gather disable" ;;
            "Done"|"") break ;;
        esac
        echo ""
    done

    if [[ "$KARGS_CHANGED" == true ]]; then
        echo "${yellow}A reboot is required for changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    fi

# Diagnose sleep/suspend issues on Framework 13 AMD
[group('Rocinante')]
diagnose-sleep:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    red=$(tput setaf 1 2>/dev/null) || red=""

    echo "${b}Sleep/Suspend Diagnostics (Framework 13 AMD)${n}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # System info
    echo "${b}System:${n}"
    echo "  Kernel:    $(uname -r)"
    FW_VER=$(rpm -q linux-firmware 2>/dev/null || echo "unknown")
    echo "  Firmware:  ${FW_VER}"
    SLEEP_MODE=$(cat /sys/power/mem_sleep 2>/dev/null || echo "unknown")
    echo "  Sleep mode: ${SLEEP_MODE}"
    echo ""

    # Known-bad firmware check
    if echo "$FW_VER" | grep -q "20260221"; then
        echo "${red}${b}⚠ WARNING: linux-firmware-20260221 has a known S0ix regression!${n}"
        echo "  S0ix entry/residency will be 0. Update firmware or use rocinante image with fix."
        echo "  See: https://github.com/bazzite-org/bazzite/issues/4356"
        echo ""
    fi

    # Kernel parameters
    echo "${b}Kernel parameters:${n}"
    CMDLINE=$(cat /proc/cmdline)
    for param in amdgpu.dcdebugmask amdgpu.sg_display amdgpu.cwsr_enable pcie_aspm.policy rtc_cmos.use_acpi_alarm; do
        val=$(echo "$CMDLINE" | tr ' ' '\n' | grep "^${param}=" || true)
        if [[ -n "$val" ]]; then
            echo "  ${green}${b}✓${n} ${val}"
        else
            echo "  ${yellow}·${n} ${param} (not set)"
        fi
    done
    echo ""

    # ACPI wakeup sources
    echo "${b}ACPI wakeup sources:${n}"
    if [[ -f /proc/acpi/wakeup ]]; then
        while read -r line; do
            if echo "$line" | grep -q "enabled"; then
                echo "  ${green}${b}✓${n} $line"
            elif echo "$line" | grep -q "XHC.*disabled"; then
                echo "  ${yellow}·${n} $line (wakeup disabled by udev rule)"
            fi
        done < /proc/acpi/wakeup || true
    else
        echo "  /proc/acpi/wakeup not available"
    fi
    echo ""

    # USB wakeup
    echo "${b}USB devices with wakeup enabled:${n}"
    for dev in /sys/bus/usb/devices/*/power/wakeup; do
        if [[ -f "$dev" ]] && [[ "$(cat "$dev" 2>/dev/null)" == "enabled" ]]; then
            devpath=$(dirname "$(dirname "$dev")")
            vendor=$(cat "${devpath}/idVendor" 2>/dev/null || echo "????")
            product=$(cat "${devpath}/idProduct" 2>/dev/null || echo "????")
            prodname=$(cat "${devpath}/product" 2>/dev/null || echo "unknown")
            echo "  ${vendor}:${product} ${prodname}"
        fi
    done
    echo ""

    # Sleep hooks
    echo "${b}Installed sleep hooks:${n}"
    for hook in /usr/lib/systemd/system-sleep/*.sh /etc/systemd/system-sleep/*.sh; do
        if [[ -f "$hook" ]]; then
            echo "  ${green}${b}✓${n} ${hook}"
        fi
    done
    echo ""

    # amd_pmc stats
    echo "${b}AMD PMC (S0ix stats):${n}"
    PMC_DIR=$(find /sys/kernel/debug/amd_pmc -maxdepth 0 2>/dev/null || true)
    if [[ -n "$PMC_DIR" && -d "$PMC_DIR" ]]; then
        for stat in s0ix_stats smu_fw_version; do
            if [[ -f "${PMC_DIR}/${stat}" ]]; then
                echo "  ${stat}:"
                sed 's/^/    /' "${PMC_DIR}/${stat}" 2>/dev/null || echo "    (permission denied — try with sudo)"
            fi
        done
    else
        echo "  ${yellow}Not accessible (try: sudo mount -t debugfs debugfs /sys/kernel/debug)${n}"
    fi
    echo ""

    # Recent suspend/resume errors
    echo "${b}Recent suspend/resume errors (last boot):${n}"
    if journalctl -b -k --priority=0..4 --grep="suspend|resume|s2idle|s0ix|amd_pmc|VPE" --no-pager -q 2>/dev/null | tail -10 | head -10; then
        true
    else
        echo "  No errors found (or journal not accessible)"
    fi
    echo ""

    # Optional suspend test
    echo "${b}Suspend test:${n}"
    echo "  To run a 10-second suspend test:"
    echo "  ${b}sudo rtcwake -m freeze -s 10${n}"
    echo ""
    echo "  Then check: ${b}sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats${n}"
    echo "  Look for non-zero 'Success' and 'Residency' values."

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
    echo "  - ujust bbrew                    # Install optional tool bundles (k8s, IDE, etc.)"
    echo "  - ujust setup-borgmatic         # Set up borgmatic backups to BorgBase"
    echo "  - ujust setup-gpu-passthrough   # If using Incus VMs with GPU passthrough"
    echo "  - ujust setup-yubikey-ssh       # If using YubiKey for SSH"
    echo "  - ujust toggle-suspend          # If using for remote access"
    echo ""
    echo "${b}First-run setup complete!${n}"

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

            if [[ -f /etc/pam.d/gdm-fingerprint ]]; then
                # GNOME/GDM: configure gdm-fingerprint for screen unlock
                echo "By default, GDM boot login uses password (to unlock keyring)."
                echo "Screen unlock can use YubiKey via gdm-fingerprint."
                echo ""

                read -p "Configure YubiKey for screen unlock? [y/N]: " unlock_confirm
                if [[ "$unlock_confirm" =~ ^[Yy]$ ]]; then
                    GDM_FP="/etc/pam.d/gdm-fingerprint"
                    if grep -q "pam_u2f.so" "$GDM_FP"; then
                        echo "${green}${b}✓${n} Already configured in gdm-fingerprint"
                    else
                        echo "Adding pam_u2f to gdm-fingerprint..."
                        sudo sed -i '1a auth     sufficient pam_u2f.so cue' "$GDM_FP"
                        echo "${green}${b}✓${n} gdm-fingerprint configured"
                    fi
                fi
            elif [[ -f /etc/pam.d/sddm ]]; then
                # KDE/SDDM: inform user about different PAM configuration
                echo "${yellow}${b}Note:${n} Screen unlock with YubiKey on SDDM (KDE) requires"
                echo "different PAM configuration than GNOME/GDM."
                echo ""
                echo "Steps 1-2 (sudo and polkit) work regardless of desktop environment."
                echo "SDDM screen unlock with pam_u2f is not configured automatically."
            else
                echo "${yellow}${b}Warning:${n} No supported display manager PAM file found."
                echo "Screen unlock configuration skipped."
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

            # Screen unlock status (desktop-aware)
            echo "${cyan}Screen unlock:${n}"
            if [[ -f /etc/pam.d/gdm-fingerprint ]]; then
                echo "  Display manager: GDM (GNOME)"
                if grep -q "pam_u2f.so" /etc/pam.d/gdm-fingerprint; then
                    echo "  ${green}YubiKey enabled via gdm-fingerprint${n}"
                else
                    echo "  ${yellow}YubiKey not configured${n} (password only)"
                fi
            elif [[ -f /etc/pam.d/sddm ]]; then
                echo "  Display manager: SDDM (KDE)"
                if grep -q "pam_u2f.so" /etc/pam.d/sddm; then
                    echo "  ${green}YubiKey enabled via sddm${n}"
                else
                    echo "  ${yellow}YubiKey not configured${n} (password only)"
                fi
            else
                echo "  Not applicable (no supported display manager found)"
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

            # Remove from display manager PAM
            if [[ -f /etc/pam.d/gdm-fingerprint ]] && grep -q "pam_u2f.so" /etc/pam.d/gdm-fingerprint; then
                sudo sed -i '/pam_u2f.so/d' /etc/pam.d/gdm-fingerprint
                echo "${green}${b}✓${n} Removed pam_u2f from gdm-fingerprint"
            fi
            if [[ -f /etc/pam.d/sddm ]] && grep -q "pam_u2f.so" /etc/pam.d/sddm; then
                sudo sed -i '/pam_u2f.so/d' /etc/pam.d/sddm
                echo "${green}${b}✓${n} Removed pam_u2f from sddm"
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

# Set up borgmatic backups to BorgBase (encrypted, automated, config-as-code)
[group('Rocinante')]
setup-borgmatic:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    cyan=$(tput setaf 6 2>/dev/null) || cyan=""

    echo "${b}Borgmatic Backup Setup${n}"
    echo ""

    CONFIG_DIR="$HOME/.config/borgmatic"
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    SSH_KEY="$HOME/.ssh/borgbase-ri"
    PASSPHRASE_FILE="$CONFIG_DIR/passphrase"
    DUMP_DIR="$HOME/backup-exports/db-dumps"
    PRE_BACKUP="$HOME/bin/borgmatic-pre-backup.sh"

    # Step 1: Install borgmatic via brew
    echo "${cyan}Step 1: Install borgmatic${n}"
    if command -v borgmatic &>/dev/null; then
        echo "${green}${b}✓${n} borgmatic already installed: $(borgmatic --version)"
    else
        echo "Installing borgmatic via brew..."
        brew install borgmatic
        echo "${green}${b}✓${n} borgmatic installed"
    fi
    if command -v borg &>/dev/null; then
        echo "${green}${b}✓${n} borg already installed: $(borg --version)"
    else
        echo "Installing borgbackup via brew..."
        brew install borgbackup
        echo "${green}${b}✓${n} borgbackup installed"
    fi
    echo ""

    # Step 2: Generate SSH key for BorgBase
    echo "${cyan}Step 2: SSH key for BorgBase${n}"
    if [[ -f "$SSH_KEY" ]]; then
        echo "${green}${b}✓${n} SSH key already exists: $SSH_KEY"
    else
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "borgbase-ri"
        echo "${green}${b}✓${n} SSH key generated: $SSH_KEY"
    fi
    echo ""
    echo "Public key (add to BorgBase):"
    echo "  $(cat "${SSH_KEY}.pub")"
    echo ""

    # Step 3: Create directory structure
    echo "${cyan}Step 3: Create directories${n}"
    mkdir -p "$CONFIG_DIR" "$SYSTEMD_DIR" "$DUMP_DIR" "$HOME/bin"
    echo "${green}${b}✓${n} Created config directories"
    echo ""

    # Step 4: Generate passphrase
    echo "${cyan}Step 4: Encryption passphrase${n}"
    if [[ -f "$PASSPHRASE_FILE" ]]; then
        echo "${green}${b}✓${n} Passphrase file already exists"
    else
        # Generate a strong random passphrase
        python3 -c "import secrets; print(secrets.token_urlsafe(32))" > "$PASSPHRASE_FILE"
        chmod 600 "$PASSPHRASE_FILE"
        echo "${green}${b}✓${n} Passphrase generated at $PASSPHRASE_FILE (chmod 600)"
        echo ""
        echo "${yellow}${b}IMPORTANT: Store this passphrase in 1Password now!${n}"
        echo "  Label: BorgBase ri — borg passphrase"
        echo "  Value: $(cat "$PASSPHRASE_FILE")"
    fi
    echo ""

    # Step 5: Create pre-backup database dump script
    echo "${cyan}Step 5: Pre-backup database dump script${n}"
    if [[ -f "$PRE_BACKUP" ]]; then
        echo "${green}${b}✓${n} Pre-backup script already exists"
    else
        cat > "$PRE_BACKUP" << 'SCRIPT'
    #!/usr/bin/env bash
    set -euo pipefail
    # borgmatic pre-backup hook: dump databases from Incus containers
    # Adjust container names and docker service names as needed

    DUMP_DIR="$HOME/backup-exports/db-dumps"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$DUMP_DIR"

    echo "Dumping databases..."

    # Immich — Postgres
    echo "  Immich (postgres)..."
    incus exec immich -- docker exec -i immich_postgres \
        pg_dump -U postgres -d immich \
        > "$DUMP_DIR/immich-postgres-${TIMESTAMP}.sql" 2>/dev/null || \
        echo "  WARNING: Immich dump failed"

    # Authentik — Postgres
    echo "  Authentik (postgres)..."
    incus exec authentik -- docker exec -i authentik-postgresql-1 \
        pg_dump -U authentik -d authentik \
        > "$DUMP_DIR/authentik-postgres-${TIMESTAMP}.sql" 2>/dev/null || \
        echo "  WARNING: Authentik dump failed"

    # Paperless — Postgres
    echo "  Paperless (postgres)..."
    incus exec paperless -- docker exec -i paperless-db-1 \
        pg_dump -U paperless -d paperless \
        > "$DUMP_DIR/paperless-postgres-${TIMESTAMP}.sql" 2>/dev/null || \
        echo "  WARNING: Paperless dump failed"

    # Forgejo — dump (includes DB + repos)
    echo "  Forgejo (dump)..."
    incus exec forgejo -- docker exec -i forgejo \
        forgejo dump -c /etc/forgejo/app.ini --type tar.gz \
        -f /tmp/forgejo-dump.tar.gz 2>/dev/null && \
    incus file pull forgejo/tmp/forgejo-dump.tar.gz \
        "$DUMP_DIR/forgejo-dump-${TIMESTAMP}.tar.gz" 2>/dev/null && \
    incus exec forgejo -- rm -f /tmp/forgejo-dump.tar.gz || \
        echo "  WARNING: Forgejo dump failed"

    # Vaultwarden — SQLite backup
    echo "  Vaultwarden (sqlite)..."
    incus exec vaultwarden -- docker exec -i vaultwarden \
        sqlite3 /data/db.sqlite3 ".backup /tmp/vaultwarden-backup.sqlite3" 2>/dev/null && \
    incus file pull vaultwarden/tmp/vaultwarden-backup.sqlite3 \
        "$DUMP_DIR/vaultwarden-${TIMESTAMP}.sqlite3" 2>/dev/null && \
    incus exec vaultwarden -- rm -f /tmp/vaultwarden-backup.sqlite3 || \
        echo "  WARNING: Vaultwarden dump failed"

    # Clean up old dumps (keep last 3)
    echo "  Cleaning old dumps..."
    for prefix in immich-postgres authentik-postgres paperless-postgres forgejo-dump vaultwarden; do
        ls -1t "$DUMP_DIR"/${prefix}-* 2>/dev/null | tail -n +4 | xargs -r rm -f
    done

    echo "Database dumps complete."
    SCRIPT
        chmod +x "$PRE_BACKUP"
        echo "${green}${b}✓${n} Created $PRE_BACKUP"
    fi
    echo ""

    # Step 6: Create borgmatic config template
    echo "${cyan}Step 6: Borgmatic config${n}"
    BORGMATIC_CONFIG="$CONFIG_DIR/config.yaml"
    if [[ -f "$BORGMATIC_CONFIG" ]]; then
        echo "${green}${b}✓${n} Config already exists: $BORGMATIC_CONFIG"
    else
        cat > "$BORGMATIC_CONFIG" << YAML
    # Borgmatic configuration for ri → BorgBase
    # Docs: https://torsion.org/borgmatic/docs/reference/configuration/

    source_directories:
        # Home directory
        - /var/home/allard

        # Database dumps (from pre-backup hook)
        - /var/home/allard/backup-exports/db-dumps

        # Incus container data (verify paths with: incus storage list / zfs list)
        # TODO: Update <pool> with actual ZFS pool name from 'incus storage list'
        - /var/lib/incus/storage-pools/<pool>/containers/immich
        - /var/lib/incus/storage-pools/<pool>/containers/paperless
        - /var/lib/incus/storage-pools/<pool>/containers/forgejo
        - /var/lib/incus/storage-pools/<pool>/containers/vaultwarden
        - /var/lib/incus/storage-pools/<pool>/containers/authentik
        - /var/lib/incus/storage-pools/<pool>/containers/actual

        # VM disk (large — consider local-only ZFS snapshots instead)
        # - /var/lib/incus/storage-pools/<pool>/virtual-machines/desktop-win10

    exclude_patterns:
        - '*.pyc'
        - '*/__pycache__'
        - '*.tmp'
        - /var/home/allard/.cache
        - /var/home/allard/.local/share/containers/storage
        - /var/home/allard/Downloads
        - /var/home/allard/.local/share/Trash
        - /var/home/allard/.mozilla
        - /var/home/allard/.var/app
        - /var/home/allard/.local/share/Steam
        - /var/home/allard/.ollama
        - /var/home/allard/nvidia-libs
        - '**/node_modules'

    repositories:
        # TODO: Replace with actual BorgBase repo URL
        - path: ssh://XXXXX@XXXXX.repo.borgbase.com/./repo
          label: borgbase-ri

    encryption_passcommand: cat /var/home/allard/.config/borgmatic/passphrase

    ssh_command: ssh -i /var/home/allard/.ssh/borgbase-ri

    compression: auto,zstd,6

    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6

    before_backup:
        - /var/home/allard/bin/borgmatic-pre-backup.sh

    checks:
        - name: repository
          frequency: 2 weeks
        - name: archives
          frequency: 1 month
    YAML
        echo "${green}${b}✓${n} Created $BORGMATIC_CONFIG"
        echo "${yellow}${b}TODO: Edit config to set BorgBase repo URL and verify Incus storage paths${n}"
    fi
    echo ""

    # Step 7: Create systemd timer
    echo "${cyan}Step 7: Systemd timer${n}"
    if [[ -f "$SYSTEMD_DIR/borgmatic.service" ]]; then
        echo "${green}${b}✓${n} borgmatic.service already exists"
    else
        cat > "$SYSTEMD_DIR/borgmatic.service" << 'UNIT'
    [Unit]
    Description=Borgmatic backup to BorgBase
    Wants=network-online.target
    After=network-online.target
    # Prevent system sleep during backup
    ConditionACPower=true

    [Service]
    Type=oneshot
    Nice=19
    IOSchedulingClass=best-effort
    IOSchedulingPriority=7
    ExecStart=%h/.linuxbrew/bin/borgmatic --verbosity -2 --syslog-verbosity 1
    UNIT
        echo "${green}${b}✓${n} Created borgmatic.service"
    fi

    if [[ -f "$SYSTEMD_DIR/borgmatic.timer" ]]; then
        echo "${green}${b}✓${n} borgmatic.timer already exists"
    else
        cat > "$SYSTEMD_DIR/borgmatic.timer" << 'UNIT'
    [Unit]
    Description=Run borgmatic backup daily

    [Timer]
    OnCalendar=*-*-* 03:00:00
    RandomizedDelaySec=30m
    Persistent=true

    [Install]
    WantedBy=timers.target
    UNIT
        echo "${green}${b}✓${n} Created borgmatic.timer"
    fi
    echo ""

    # Step 8: Enable timer
    echo "${cyan}Step 8: Enable timer${n}"
    systemctl --user daemon-reload
    systemctl --user enable borgmatic.timer
    systemctl --user start borgmatic.timer
    echo "${green}${b}✓${n} borgmatic.timer enabled and started"

    # Enable lingering so timers run without login
    if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
        echo "Enabling linger for $(whoami)..."
        loginctl enable-linger "$(whoami)"
        echo "${green}${b}✓${n} Linger enabled"
    else
        echo "${green}${b}✓${n} Linger already enabled"
    fi
    echo ""

    # Summary
    echo "${b}Setup complete!${n}"
    echo ""
    echo "${b}Next steps:${n}"
    echo "  1. Create a BorgBase repo at https://www.borgbase.com"
    echo "     - Add the SSH public key shown above"
    echo "     - Enable append-only mode"
    echo "     - Copy the repo URL"
    echo ""
    echo "  2. Edit borgmatic config with your repo URL:"
    echo "     ${b}\$EDITOR $BORGMATIC_CONFIG${n}"
    echo ""
    echo "  3. Verify Incus storage paths and update config:"
    echo "     ${b}incus storage list${n}"
    echo "     ${b}zfs list${n}"
    echo ""
    echo "  4. Verify the pre-backup script container/service names:"
    echo "     ${b}\$EDITOR $PRE_BACKUP${n}"
    echo ""
    echo "  5. Initialize the borg repo:"
    echo "     ${b}borgmatic init --encryption repokey-blake2${n}"
    echo ""
    echo "  6. Run first backup:"
    echo "     ${b}borgmatic create --verbosity 2 --list${n}"
    echo ""
    echo "  7. Test restore:"
    echo "     ${b}borgmatic extract --archive latest --path <file> --destination /tmp/restore-test${n}"
    echo ""
    echo "  8. Export and save repo key in 1Password:"
    echo "     ${b}borgmatic key export --directory /tmp/${n}"
    echo "     Label: BorgBase ri — borg repo key"
    echo ""
    echo "  9. Store passphrase in 1Password:"
    echo "     Label: BorgBase ri — borg passphrase"
    echo "     ${b}cat $PASSPHRASE_FILE${n}"
    echo ""
    echo "  Timer status: ${b}systemctl --user status borgmatic.timer${n}"
    echo "  Manual run:   ${b}systemctl --user start borgmatic.service${n}"

# Set up suspend-then-hibernate (macOS-style sleep)
[group('Rocinante')]
setup-hibernate:
    #!/usr/bin/env bash
    set -euo pipefail
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    red=$(tput setaf 1 2>/dev/null) || red=""
    cyan=$(tput setaf 6 2>/dev/null) || cyan=""

    echo "${b}Suspend-then-Hibernate Setup${n}"
    echo ""
    echo "This sets up macOS-style sleep: suspend to RAM for 30 minutes,"
    echo "then hibernate to disk for zero battery drain."
    echo ""

    # Pre-flight checks
    if grep -q '\[disabled\]' /sys/power/disk 2>/dev/null; then
        echo "${red}${b}Error:${n} Hibernate is disabled by the kernel."
        echo "This usually means Secure Boot is enabled. Disable it in BIOS first."
        exit 1
    fi

    if [[ -f /var/swap/swapfile ]]; then
        echo "${yellow}${b}Warning:${n} Hibernate appears already configured (/var/swap/swapfile exists)."
        echo "Run ${b}ujust remove-hibernate${n} first to reconfigure."
        exit 1
    fi

    if [[ -f /etc/systemd/logind.conf.d/no-suspend.conf ]]; then
        echo "${yellow}${b}Warning:${n} Suspend is currently disabled (no-suspend.conf)."
        echo "Hibernate requires suspend. Run ${b}ujust toggle-suspend${n} to re-enable it first."
        echo ""
        read -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    MEM_GB=$(( MEM_KB / 1024 / 1024 ))
    echo "  RAM: ${MEM_GB}GB — swapfile will be ${MEM_GB}GB"
    echo ""
    read -p "Proceed with setup? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""

    # Step 1: Create btrfs swap subvolume + swapfile
    echo "${cyan}Step 1: Create swap subvolume and swapfile${n}"
    sudo btrfs subvolume create /var/swap
    sudo chattr +C /var/swap
    sudo btrfs filesystem mkswapfile --size "${MEM_KB}k" --uuid clear /var/swap/swapfile
    echo "${green}${b}✓${n} Created /var/swap/swapfile (${MEM_GB}GB)"
    echo ""

    # Step 2: SELinux labeling
    echo "${cyan}Step 2: SELinux labeling${n}"
    if command -v semanage &>/dev/null; then
        sudo semanage fcontext -a -t swapfile_t '/var/swap(/.*)?' 2>/dev/null || true
        sudo restorecon -RF /var/swap
        echo "${green}${b}✓${n} SELinux context set (swapfile_t)"
    else
        echo "${yellow}·${n} semanage not available, skipping SELinux labeling"
    fi
    echo ""

    # Step 3: Add fstab entry + activate swap
    echo "${cyan}Step 3: Configure fstab and activate swap${n}"
    sudo cp /etc/fstab /etc/fstab.bak.hibernate
    if ! grep -q '/var/swap/swapfile' /etc/fstab; then
        printf '\n# Btrfs swapfile for suspend-then-hibernate\n/var/swap/swapfile none swap defaults,pri=0 0 0\n' | sudo tee -a /etc/fstab > /dev/null
    fi
    sudo swapon -p 0 /var/swap/swapfile
    echo "${green}${b}✓${n} Swap activated and added to fstab"
    echo ""

    # Step 4: Get resume parameters
    echo "${cyan}Step 4: Determine resume parameters${n}"
    RESUME_UUID=$(findmnt -no UUID -T /var/swap/swapfile)
    RESUME_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
    echo "  resume=UUID=${RESUME_UUID}"
    echo "  resume_offset=${RESUME_OFFSET}"
    echo "${green}${b}✓${n} Resume parameters determined"
    echo ""

    # Step 5: Set kernel args
    echo "${cyan}Step 5: Set kernel boot parameters${n}"
    sudo rpm-ostree kargs \
        --append-if-missing="resume=UUID=${RESUME_UUID}" \
        --append-if-missing="resume_offset=${RESUME_OFFSET}"
    echo "${green}${b}✓${n} Kernel args set"
    echo ""

    # Step 6: Enable dracut resume module
    echo "${cyan}Step 6: Enable dracut resume module${n}"
    echo 'add_dracutmodules+=" resume "' | sudo tee /etc/dracut.conf.d/resume.conf > /dev/null
    sudo rpm-ostree initramfs --enable 2>/dev/null || true
    echo "${green}${b}✓${n} Dracut resume module enabled"
    echo "${yellow}  Note: Future system updates will be slower (initramfs rebuild on each update)${n}"
    echo ""

    # Step 7: Configure systemd sleep
    echo "${cyan}Step 7: Configure suspend-then-hibernate (30min delay)${n}"
    sudo mkdir -p /etc/systemd/sleep.conf.d
    sudo tee /etc/systemd/sleep.conf.d/hibernate.conf > /dev/null << 'SLEEPCONF'
    [Sleep]
    AllowSuspendThenHibernate=yes
    HibernateDelaySec=30min
    SLEEPCONF
    echo "${green}${b}✓${n} Sleep config installed (30 minute delay)"
    echo ""

    # Step 8: Configure logind for lid close
    echo "${cyan}Step 8: Configure lid close behavior${n}"
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee /etc/systemd/logind.conf.d/hibernate.conf > /dev/null << 'LOGINDCONF'
    [Login]
    HandleLidSwitch=suspend-then-hibernate
    HandleLidSwitchExternalPower=suspend-then-hibernate
    LOGINDCONF
    sudo systemctl restart systemd-logind
    echo "${green}${b}✓${n} Logind configured for suspend-then-hibernate on lid close"
    echo ""

    # Summary
    echo "${green}${b}Setup complete!${n}"
    echo ""
    echo "${b}What was configured:${n}"
    echo "  • Swapfile: /var/swap/swapfile (${MEM_GB}GB)"
    echo "  • Kernel: resume=UUID=${RESUME_UUID} resume_offset=${RESUME_OFFSET}"
    echo "  • Dracut: resume module enabled"
    echo "  • Sleep: suspend-then-hibernate with 30 minute delay"
    echo "  • Logind: lid close triggers suspend-then-hibernate"
    echo ""
    echo "${b}On lid close:${n} suspend → 30min → hibernate → zero battery drain"
    echo "${b}On wake:${n} instant (within 30min) or ~15s resume + LUKS password (after hibernate)"
    echo ""
    echo "${yellow}A reboot is required for kernel parameter and initramfs changes.${n}"
    echo ""
    read -p "Reboot now? [y/N]: " reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        systemctl reboot
    else
        echo "Please reboot when convenient: ${b}systemctl reboot${n}"
    fi

# Remove suspend-then-hibernate configuration
[group('Rocinante')]
remove-hibernate:
    #!/usr/bin/env bash
    set -euo pipefail
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    red=$(tput setaf 1 2>/dev/null) || red=""

    echo "${b}Remove Suspend-then-Hibernate${n}"
    echo ""

    if [[ ! -f /var/swap/swapfile ]] && [[ ! -f /etc/systemd/sleep.conf.d/hibernate.conf ]]; then
        echo "Hibernate is not configured. Nothing to remove."
        exit 0
    fi

    echo "This will remove all hibernate configuration:"
    echo "  • Swapfile and swap subvolume"
    echo "  • Kernel resume parameters"
    echo "  • Dracut resume module"
    echo "  • Sleep and logind configuration"
    echo ""
    read -p "Continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""

    KARGS_CHANGED=false

    # Remove logind config
    if [[ -f /etc/systemd/logind.conf.d/hibernate.conf ]]; then
        sudo rm -f /etc/systemd/logind.conf.d/hibernate.conf
        sudo systemctl restart systemd-logind
        echo "${green}${b}✓${n} Removed logind hibernate config"
    fi

    # Remove sleep config
    if [[ -f /etc/systemd/sleep.conf.d/hibernate.conf ]]; then
        sudo rm -f /etc/systemd/sleep.conf.d/hibernate.conf
        echo "${green}${b}✓${n} Removed sleep hibernate config"
    fi

    # Remove kernel args
    CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
    RESUME_PARAM=$(echo "$CURRENT_KARGS" | tr ' ' '\n' | grep "^resume=UUID=" || true)
    OFFSET_PARAM=$(echo "$CURRENT_KARGS" | tr ' ' '\n' | grep "^resume_offset=" || true)
    if [[ -n "$RESUME_PARAM" ]]; then
        sudo rpm-ostree kargs --delete-if-present="$RESUME_PARAM"
        KARGS_CHANGED=true
        echo "${green}${b}✓${n} Removed kernel arg: $RESUME_PARAM"
    fi
    if [[ -n "$OFFSET_PARAM" ]]; then
        sudo rpm-ostree kargs --delete-if-present="$OFFSET_PARAM"
        KARGS_CHANGED=true
        echo "${green}${b}✓${n} Removed kernel arg: $OFFSET_PARAM"
    fi

    # Remove dracut config
    if [[ -f /etc/dracut.conf.d/resume.conf ]]; then
        sudo rm -f /etc/dracut.conf.d/resume.conf
        echo "${green}${b}✓${n} Removed dracut resume config"
    fi

    # Disable initramfs overlay
    if rpm-ostree status 2>/dev/null | grep -q "initramfs"; then
        sudo rpm-ostree initramfs --disable 2>/dev/null || true
        KARGS_CHANGED=true
        echo "${green}${b}✓${n} Disabled initramfs overlay (faster future updates)"
    fi

    # Turn off swap and remove swapfile
    if [[ -f /var/swap/swapfile ]]; then
        sudo swapoff /var/swap/swapfile 2>/dev/null || true
        sudo rm -f /var/swap/swapfile
        sudo btrfs subvolume delete /var/swap 2>/dev/null || sudo rm -rf /var/swap
        echo "${green}${b}✓${n} Removed swapfile and swap subvolume"
    fi

    # Remove fstab entry
    if grep -q '/var/swap/swapfile' /etc/fstab 2>/dev/null; then
        sudo sed -i '/\/var\/swap\/swapfile/d' /etc/fstab
        sudo sed -i '/Btrfs swapfile for suspend-then-hibernate/d' /etc/fstab
        echo "${green}${b}✓${n} Removed fstab swap entry"
    fi

    # Remove SELinux context
    if command -v semanage &>/dev/null; then
        sudo semanage fcontext -d '/var/swap(/.*)?' 2>/dev/null || true
        echo "${green}${b}✓${n} Removed SELinux context"
    fi

    # Restore fstab backup if exists
    if [[ -f /etc/fstab.bak.hibernate ]]; then
        sudo rm -f /etc/fstab.bak.hibernate
    fi

    echo ""
    echo "${green}${b}Hibernate configuration removed.${n}"

    if [[ "$KARGS_CHANGED" == true ]]; then
        echo ""
        echo "${yellow}A reboot is required for kernel parameter changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    fi
