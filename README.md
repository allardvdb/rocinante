# rocinante

Custom [Bluefin-DX](https://projectbluefin.io/) image with 1Password, OpenVPN, and YubiKey support.

## Installation

```bash
# Standard
sudo bootc switch ghcr.io/allardvdb/rocinante

# NVIDIA
sudo bootc switch ghcr.io/allardvdb/rocinante-nvidia
```

## First-Time Setup

```bash
ujust first-run
```

Individual recipes:
- `ujust setup-1password-browser` — Flatpak browser integration
- `ujust setup-yubikey-ssh` — YubiKey SSH authentication
- `ujust toggle-openvpn-indicator` — OpenVPN tray icon
- `ujust toggle-suspend` — Disable suspend for remote access

## What's Included

| Software | Notes |
|----------|-------|
| 1Password | Desktop + CLI |
| OpenVPN3 | Indicator disabled by default |
| tmux | Terminal multiplexer |
| nvidia-container-toolkit | NVIDIA variant only |

## Docs

- [1Password + Flatpak Browsers](docs/1password-flatpak-fix.md)
- [YubiKey + Fingerprint Auth](docs/yubikey-1password-authentication.md)

## Building

```bash
just build              # Build image
just build-iso          # Create installer ISO
just build-iso-nvidia   # Create NVIDIA installer ISO
```

## Links

- [Universal Blue](https://universal-blue.org/)
- [Bluefin](https://projectbluefin.io/)
