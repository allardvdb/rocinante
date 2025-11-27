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
        cat > ~/.gnupg/scdaemon.conf << 'EOF'
# Disable scdaemon's built-in CCID driver to prevent race condition with pcscd
disable-ccid

# Allow shared access to the card (needed when opensc/other apps also use it)
pcsc-shared
EOF
        echo "Created ~/.gnupg/scdaemon.conf"
    else
        echo "~/.gnupg/scdaemon.conf already exists, skipping"
    fi

    # Update gpg-agent.conf for SSH support
    if ! grep -q "enable-ssh-support" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
        cat >> ~/.gnupg/gpg-agent.conf << 'EOF'

# SSH support
enable-ssh-support
default-cache-ttl-ssh 600
max-cache-ttl-ssh 7200
EOF
        echo "Added SSH support to ~/.gnupg/gpg-agent.conf"
    else
        echo "SSH support already configured in gpg-agent.conf"
    fi

    # Create bashrc.d directory and GPG/YubiKey script
    mkdir -p ~/.bashrc.d

    if [[ ! -f ~/.bashrc.d/gpg-yubikey.sh ]]; then
        cat > ~/.bashrc.d/gpg-yubikey.sh << 'EOF'
#!/bin/bash
# GPG and Yubikey SSH configuration

# Set GPG TTY
export GPG_TTY=$(tty)

# Use gpg-agent for SSH
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)

# Ensure gpg-agent is running with SSH support
if ! pgrep -x gpg-agent > /dev/null; then
    gpg-agent --daemon --enable-ssh-support > /dev/null 2>&1
fi

# Update the gpg-agent TTY (for pinentry)
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
EOF
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
