# 1Password + Flatpak Browser Integration

## The Problem

1Password's BrowserSupport binary verifies the parent process, but with Flatpak browsers it sees `/usr/libexec/flatpak-session-helper` instead of the browser, causing "connection problem" errors.

## The Solution

Run the setup recipe after installation:

```bash
ujust setup-1password-browser
```

This automatically:
1. Detects installed Flatpak browsers (Firefox, Chrome, Brave, Chromium)
2. Downloads and runs the FlyinPancake community integration script
3. Configures each detected browser

After running, restart your browser(s) and verify the 1Password extension connects.

## What It Does

The integration script (FlyinPancake/1password-flatpak-browser-integration):
1. Grants browser permission to run programs outside sandbox (`org.freedesktop.Flatpak` talk permission)
2. Creates wrapper script at `~/.var/app/<browser>/data/bin/1password-wrapper.sh`
3. Updates native messaging host config to use the wrapper

For Firefox Flatpak specifically, the config is placed at:
- `~/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts/com.1password.1password.json`

The rocinante image pre-configures:
- `/etc/1password/custom_allowed_browsers` with `flatpak-session-helper`

## Important Notes

- Works for all Flatpak browsers, not just Firefox
- Slightly weakens Flatpak sandbox (allows execution outside sandbox)
- Same issue affects Bitwarden, KeePassXC, and other password managers
- Can be re-run if you install additional Flatpak browsers

## Verification

- Extension should show "Integration status: Connected"
- Desktop app unlock should unlock browser extension
- Check logs if issues: `~/.config/1Password/logs/BrowserSupport/`

## Manual Setup

If you prefer manual setup or need to troubleshoot:

```bash
# Clone and run the community integration script
cd /tmp
git clone https://github.com/FlyinPancake/1password-flatpak-browser-integration
cd 1password-flatpak-browser-integration
./1password-flatpak-browser-integration.sh
# Enter browser ID when prompted, e.g.: org.mozilla.firefox
```

## References

- https://github.com/FlyinPancake/1password-flatpak-browser-integration
- https://1password.community/discussion/122270/flatpak-firefox-integration