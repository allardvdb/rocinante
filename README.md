# rocinante

Custom [Bluefin](https://projectbluefin.io/) image with 1Password, Homebrew, and YubiKey support.

Built using the [finpilot](https://github.com/projectbluefin/finpilot) pattern.

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
- `ujust toggle-suspend` — Disable suspend for remote access

## What's included on top of vanilla Bluefin

| Software | Notes |
|----------|-------|
| 1Password | Desktop + CLI + Flatpak browser integration |
| Homebrew | Via @ublue-os/brew (auto-setup and update timers) |
| nvidia-container-toolkit | NVIDIA variant only |
| Custom ujust recipes | YubiKey, 1Password browser setup, suspend toggle |

## Project Structure

```
.
├── build/                    # Numbered build scripts (run during image build)
│   ├── 10-build.sh          # Main orchestrator
│   ├── 20-1password.sh      # 1Password installation
│   └── copr-helpers.sh      # COPR helper functions
├── custom/                   # Custom files copied into the image
│   ├── brew/                 # Brewfiles for Homebrew packages
│   │   └── default.Brewfile
│   └── ujust/                # Custom ujust recipes (→ 60-custom.just)
│       └── rocinante.just
├── Containerfile             # Container build definition (ctx-stage pattern)
└── .github/workflows/        # CI: build, validate, clean
```

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
- [finpilot](https://github.com/projectbluefin/finpilot) — upstream template
