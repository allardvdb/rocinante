# 1Password + Firefox Flatpak Integration - WORKING SOLUTION
*Tested and working: October 27, 2025 on Bluefin Linux*

## The Problem
1Password's BrowserSupport binary verifies the parent process, but with Firefox Flatpak it sees `/usr/libexec/flatpak-session-helper` instead of Firefox, causing "connection problem" errors.

## The Solution (What Actually Works)

Use the **FlyinPancake/1password-flatpak-browser-integration** community script:

```bash
# 1. Allow flatpak-session-helper in 1Password
echo "flatpak-session-helper" | sudo tee /etc/1password/custom_allowed_browsers

# 2. Clone and run the community integration script
cd /tmp
git clone https://github.com/FlyinPancake/1password-flatpak-browser-integration
cd 1password-flatpak-browser-integration
./1password-flatpak-browser-integration.sh

# 3. When prompted, enter: org.mozilla.firefox

# 4. Restart both applications
pkill firefox
pkill 1password

# 5. Start 1Password first, then Firefox
# The extension should now connect!
```

## What the Script Does
1. Grants Firefox permission to run programs outside sandbox (`org.freedesktop.Flatpak` talk permission)
2. Creates wrapper script at `~/.var/app/org.mozilla.firefox/data/bin/1password-wrapper.sh`
3. Updates native messaging host config to use the wrapper
4. Adds `flatpak-session-helper` to 1Password's allowed browsers list

## Important Notes
- This is the **official community solution** maintained by FlyinPancake
- Works for all Flatpak browsers, not just Firefox
- Slightly weakens Flatpak sandbox (allows execution outside sandbox)
- Same issue affects Bitwarden, KeePassXC, and other password managers

## For Your rocinante Build

Add to `/var/home/allard/src/rocinante/build_files/build.sh`:

```bash
# Configure 1Password + Firefox Flatpak integration
cat > /etc/skel/.config/autostart/1password-flatpak-setup.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=1Password Flatpak Setup
Exec=/usr/local/bin/setup-1password-flatpak.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Set up 1Password for Flatpak browsers on first login
EOF

cat > /usr/local/bin/setup-1password-flatpak.sh << 'EOF'
#!/bin/bash
# Auto-setup 1Password Flatpak integration on first login
if [ ! -f ~/.config/1password-flatpak-configured ]; then
    # Check if Firefox Flatpak is installed
    if flatpak list | grep -q org.mozilla.firefox; then
        # Download and run integration script
        cd /tmp
        git clone https://github.com/FlyinPancake/1password-flatpak-browser-integration
        cd 1password-flatpak-browser-integration
        echo "org.mozilla.firefox" | ./1password-flatpak-browser-integration.sh
        touch ~/.config/1password-flatpak-configured
        notify-send "1Password Setup" "Firefox Flatpak integration configured. Please restart Firefox."
    fi
fi
EOF

chmod +x /usr/local/bin/setup-1password-flatpak.sh

# Ensure custom_allowed_browsers exists
mkdir -p /etc/1password
echo "flatpak-session-helper" > /etc/1password/custom_allowed_browsers
```

## Verification
- Check logs: `~/.config/1Password/logs/BrowserSupport/`
- Extension should show "Integration status: Connected"
- Desktop app unlock should unlock browser extension

## References
- https://github.com/FlyinPancake/1password-flatpak-browser-integration
- https://1password.community/discussion/122270/flatpak-firefox-integration
- https://universal-blue.discourse.group/t/1password-with-browser-integration/10880