#!/usr/bin/bash
set -eoux pipefail
# shellcheck source=build/copr-helpers.sh
source /ctx/build/copr-helpers.sh

echo "::group:: Install Ghostty"
# scottames/ghostty is the COPR cited by ghostty.org/docs/install/binary.
# Verified: build 10407077 (ghostty 1.3.1-2) succeeded on fedora-44-x86_64/aarch64.
# gtk4-layer-shell is a declared RPM dependency — it pulls automatically.
copr_install_isolated "scottames/ghostty" \
    ghostty \
    ghostty-terminfo \
    ghostty-shell-integration
echo "::endgroup::"

echo "::group:: Install Ghostty skeleton config"
# Ghostty does not yet read /etc/ghostty/config or /etc/xdg/ghostty/config
# (upstream issue #4506 is open and unimplemented as of 2026-06).
# Ship a skeleton config so new users get OSC 52 enabled out of the box.
# Existing users are unaffected — skel only applies at account creation.
install -D -m0644 /ctx/custom/ghostty/config \
    /etc/skel/.config/ghostty/config
echo "::endgroup::"

echo "::group:: Set Ghostty as image-level default terminal (GNOME/xdg-terminal-exec)"
# xdg-terminal-exec priority: ~/.config/xdg-terminals.list (user)
#   > /etc/xdg/xdg-terminals.list (sysadmin / this file)
#   > /usr/share/xdg-terminal-exec/xdg-terminals.list (image default)
# We write the middle tier so users can override with their own ~/.config file.
# Aurora/KDE does not consult xdg-terminals.list for Dolphin or its own
# keyboard shortcuts, so this is harmless on the aurora variant.
mkdir -p /etc/xdg
printf 'com.mitchellh.ghostty.desktop\n' > /etc/xdg/xdg-terminals.list
echo "::endgroup::"
