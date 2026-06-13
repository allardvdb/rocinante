# rocinante

Custom [Bluefin](https://projectbluefin.io/) / [Aurora](https://getaurora.dev/) image with 1Password, Homebrew, Incus, and YubiKey support.

Built using the [finpilot](https://github.com/projectbluefin/finpilot) pattern. Available in GNOME (Bluefin), GNOME + NVIDIA, and KDE Plasma (Aurora) variants.

## Installation

```bash
# GNOME (Bluefin)
sudo bootc switch ghcr.io/allardvdb/rocinante

# GNOME + NVIDIA
sudo bootc switch ghcr.io/allardvdb/rocinante-nvidia

# KDE Plasma (Aurora)
sudo bootc switch ghcr.io/allardvdb/rocinante-aurora
```

## Release Streams

Images are published in three release streams:

| Stream | Tag | Purpose |
|--------|-----|---------|
| `stable` | `:stable` | Daily drivers — manually promoted via GitHub Release |
| `testing` | `:testing` | Pre-release soak — promoted via GitHub pre-release |
| `latest` | `:latest` | Bleeding edge — every push to main and daily cron |

Each stream also has date-pinned tags (e.g., `:stable.20260311`) for rollback.

### Switching streams

```bash
ujust switch-stream
```

Or manually:

```bash
sudo bootc switch ghcr.io/allardvdb/rocinante:stable --enforce-container-sigpolicy
```

### Image references

```
ghcr.io/allardvdb/rocinante:stable
ghcr.io/allardvdb/rocinante-nvidia:stable
ghcr.io/allardvdb/rocinante-aurora:stable
```

Replace `:stable` with `:testing` or `:latest` as needed.

## First-Time Setup

```bash
ujust first-run
```

Individual recipes:
- `ujust switch-stream` — Switch between stable/testing/latest release streams
- `ujust setup-1password-browser` — Flatpak browser integration
- `ujust setup-yubikey-ssh` — YubiKey SSH authentication
- `ujust enable-yubikey-gpg` — Prepare shell for GPG operations with YubiKey 5
- `ujust toggle-suspend` — Disable suspend for remote access
- `ujust setup-gpu-passthrough` — IOMMU + Incus GPU passthrough
- `ujust configure-yubikey-pam` — YubiKey PAM authentication
- `ujust setup-borgmatic` — Borgmatic backups to BorgBase

## What's included on top of vanilla Bluefin / Aurora

| Software | Notes |
|----------|-------|
| 1Password | Desktop + CLI + Flatpak browser integration |
| Homebrew | Via @ublue-os/brew (auto-setup and update timers) |
| Incus | VM/container manager with QEMU, SPICE, OVMF, VFIO |
| virt-viewer | SPICE client for `incus console --type=vga` |
| ROCm | AMD GPU compute stack |
| nvidia-container-toolkit | NVIDIA variant only |
| Custom ujust recipes | YubiKey, 1Password, GPU passthrough, borgmatic, and more |

## Project Structure

```
.
├── build/                    # Numbered build scripts (run during image build)
│   ├── 10-build.sh          # Main orchestrator
│   ├── 20-1password.sh      # 1Password installation
│   ├── 30-incus.sh          # Incus + QEMU/SPICE/VFIO
│   ├── 40-rocm.sh           # AMD ROCm compute stack
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
just build                        # Build image (default: rocinante)
just build rocinante-aurora       # Build Aurora (KDE) variant
just build-iso                    # Create GNOME installer ISO
just build-iso-nvidia             # Create GNOME + NVIDIA installer ISO
```

## Links

- [Universal Blue](https://universal-blue.org/)
- [Bluefin](https://projectbluefin.io/)
- [finpilot](https://github.com/projectbluefin/finpilot) — upstream template
