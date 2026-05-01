<!-- This file is tool-agnostic guidance for AI coding agents. -->

# AGENTS.md

## Git Workflow

**All changes must go through a branch and pull request.**

- Never commit directly to `main` — branch protection is enabled
- Create a feature branch for all changes (even small ones)
- Create a PR for review before merging
- Use descriptive branch names (e.g., `fix-1password-docs`, `add-new-recipe`)

## Repository Overview

This is a custom Universal Blue / Bluefin Linux image that creates a personalized developer workstation based on Fedora Atomic Desktop (Silverblue for GNOME, Kinoite for KDE). The image is built using GitHub Actions and published to GitHub Container Registry (ghcr.io).

**Name**: rocinante (named after the Martian gunship from The Expanse)

**Template**: Built following the [finpilot](https://github.com/projectbluefin/finpilot) pattern — the upstream-recommended way to build custom Bluefin images.

## Project Structure

```
.
├── .github/
│   ├── renovate.json5         # Renovate config (OCI digest pinning, GH Actions SHA updates)
│   └── workflows/
│       ├── build.yml          # Main build workflow (build + push to GHCR)
│       ├── build-disk.yml     # Disk image builds (ISO, QCOW2)
│       ├── clean.yml          # Weekly cleanup of old GHCR images
│       ├── validate-brewfiles.yml   # Brewfile validation on PRs
│       ├── validate-justfiles.yml   # Justfile format check on PRs
│       └── validate-shellcheck.yml  # Shellcheck on build/*.sh on PRs
├── build/                     # Build scripts (numbered, run during image build)
│   ├── 10-build.sh           # Main orchestrator (brew, packages, ujust, systemd)
│   ├── 20-1password.sh       # 1Password desktop + CLI installation
│   ├── 30-incus.sh           # Incus VM manager + QEMU/SPICE/VFIO
│   ├── 40-rocm.sh            # AMD ROCm compute stack
│   ├── 50-firmware.sh        # linux-firmware version override (Koji)
│   └── copr-helpers.sh       # COPR helper functions (sourced by build scripts)
├── custom/                    # Custom files copied into the image at build time
│   ├── brew/                  # Brewfiles for Homebrew packages
│   │   └── default.Brewfile  # Default package list
│   ├── systemd/
│   │   └── system-sleep/
│   │       └── 50-unmount-fuse.sh  # GVFS/FUSE unmount before suspend
│   ├── udev/
│   │   └── 99-disable-goodix-fingerprint.rules  # Disable fingerprint reader (S0ix)
│   └── ujust/                 # Custom ujust recipes
│       └── rocinante.just    # Rocinante-specific recipes (→ 60-custom.just)
├── disk_config/               # Disk image configurations (ISO, QCOW2, KDE/GNOME)
├── docs/                      # Documentation
├── Containerfile              # Container build definition (ctx-stage pattern, BASE_IMAGE arg)
├── Justfile                   # Local development commands
└── .pre-commit-config.yaml    # Pre-commit hooks (JSON/TOML/YAML, Brewfile)
```

## Build Architecture (ctx-stage pattern)

The Containerfile uses a two-stage build following the finpilot pattern:

1. **`scratch` ctx stage**: Copies `build/`, `custom/`, and `@ublue-os/brew` OCI files into a staging area
2. **Final stage**: Mounts the ctx stage read-only at `/ctx` and runs `build/10-build.sh`

This means build scripts and custom files are never `COPY`'d into the final image — they're only available during the build via the `/ctx` mount.

### How build scripts work
- `build/10-build.sh` is the main orchestrator:
  - Installs Homebrew via `rsync` from `/ctx/oci/brew/`
  - Copies Brewfiles to `/usr/share/ublue-os/homebrew/`
  - Concatenates `custom/ujust/*.just` into `/usr/share/ublue-os/just/60-custom.just`
  - Copies udev rules from `custom/udev/` to `/etc/udev/rules.d/`
  - Installs systemd sleep hooks from `custom/systemd/system-sleep/` to `/usr/lib/systemd/system-sleep/`
  - Installs dnf5 packages
  - Configures systemd units
  - Calls additional numbered scripts (`20-1password.sh`, `30-incus.sh`, `40-rocm.sh`, `50-firmware.sh`)

### ujust recipes (60-custom.just)
Bluefin's `00-entry.just` includes `import? "/usr/share/ublue-os/just/60-custom.just"`. The build script concatenates all `.just` files from `custom/ujust/` into this file, so recipes are automatically available via `ujust`.

## Base Images

Three variants are built from different base images:
- **rocinante**: `ghcr.io/ublue-os/bluefin:stable` (GNOME)
- **rocinante-nvidia**: `ghcr.io/ublue-os/bluefin-nvidia-open:stable` (GNOME + NVIDIA)
- **rocinante-aurora**: `ghcr.io/ublue-os/aurora:stable` (KDE Plasma)

All variants share the same build scripts and customizations. The Containerfile accepts `BASE_IMAGE` (variant selection) and `FIRMWARE_VERSION` (linux-firmware pin, default `20260309`) build args. Developer tools are managed via Homebrew (@ublue-os/brew).

## Key Customizations

### 1Password Integration
- Desktop app installed via RPM
- CLI tool (op) installed and configured
- Flatpak browser integration via ujust recipe
- SSH agent integration for Git operations
- Located in: `build/20-1password.sh`

**User Setup**: Run `ujust setup-1password-browser` after installation

### Homebrew (@ublue-os/brew)
- Installed via OCI layer in ctx stage, deployed by `10-build.sh`
- `brew-setup.service` runs on first boot to initialize Homebrew
- `brew-update.timer` and `brew-upgrade.timer` keep packages current
- Brewfiles in `custom/brew/` are copied to `/usr/share/ublue-os/homebrew/`

### Kernel Pin (removed 2026-05-01)
- The build no longer pins the kernel; the upstream Bluefin base supplies it.
- Removed under exit criterion (3) of `docs/amdgpu-strix-point-gpu-hang.md`, driven by CVE-2026-31431 which requires kernel ≥ 6.19.12-200.fc43.
- See the historical section in that doc for context if it ever needs to come back. **Do not** reinstate a bare `dracut --force` invocation in a future pin script — it produces an initramfs missing the ostree dracut module and bricks boot.

### Firmware Override
- `build/50-firmware.sh` pins `linux-firmware` to a known-good version from Koji
- Fixes S0ix regression introduced in `linux-firmware-20260221` on AMD Strix Point
- Version controlled via `FIRMWARE_VERSION` build arg in Containerfile
- Dynamically discovers ALL installed firmware sub-packages before removal and reinstalls them all at the pinned version, preserving firmware for all hardware (Intel WiFi, Broadcom, MediaTek, AMD, etc.)
- Validates Koji URLs before removing packages to fail early on package renames or missing versions

### Sleep/Suspend Fixes (Framework 13 AMD)
- Goodix fingerprint reader disabled via udev rule (`custom/udev/99-disable-goodix-fingerprint.rules`)
- XHC (USB controller) wakeup disabled via udev rule to prevent spurious s2idle wakes (`custom/udev/90-disable-xhc-wakeup.rules`)
- Suspend-then-hibernate via `ujust setup-hibernate` / `ujust remove-hibernate` (swap, initramfs, kernel args, logind)
- GVFS/FUSE mounts lazy-unmounted before suspend (`custom/systemd/system-sleep/50-unmount-fuse.sh`)
- Machine-specific fixes applied via `ujust fix-sleep` (kernel params, wakeup source management)
- Diagnostics via `ujust diagnose-sleep`
- Details: `docs/amdgpu-strix-point-gpu-hang.md`

### System Configuration
- Custom package installations via dnf5
- Immutable system patterns (using /usr/libexec, not /usr/local)

## Build System

### GitHub Actions Workflow
- Triggers on: push to main, PRs, daily schedule (10:05 UTC)
- Uses Buildah for container building
- Builds a matrix of three variants: rocinante, rocinante-nvidia, rocinante-aurora
- Publishes to: `ghcr.io/allardvdb/rocinante`, `ghcr.io/allardvdb/rocinante-nvidia`, `ghcr.io/allardvdb/rocinante-aurora`
- Signs images with Cosign
- Tags: latest, latest.YYYYMMDD, YYYYMMDD

### Validation Workflows (PRs only)
- `validate-shellcheck.yml` — shellcheck on `build/*.sh`
- `validate-justfiles.yml` — just fmt check on `custom/ujust/` and `Justfile`
- `validate-brewfiles.yml` — Brewfile syntax validation

### Building Locally
```bash
# Build the container image
just build

# Or directly with podman
podman build -t rocinante:local .
```

## Development Patterns

### Package Placement Priority

| Priority | Method | When to use |
|----------|--------|-------------|
| 1 | Homebrew (Brewfile) | CLI tools, dev dependencies |
| 2 | Flatpak | GUI desktop applications |
| 3 | dnf5 (build script) | System libraries, services needing deep integration |
| 4 | Direct install (build script) | Software not in any package manager |

**Never use dnf5 in ujust files.** ujust recipes run on the live immutable system where dnf5 cannot install packages. Use `brew` or `flatpak` in ujust recipes instead.

### File Locations in Immutable Systems
- Use `/usr/libexec/` for system executables (not `/usr/local/bin`)
- Use `/usr/lib/` for application files
- Use `/etc/` for system configuration
- Use `/var/` for mutable state

### Adding New Features
1. Create a new numbered script in `build/` (e.g., `30-feature.sh`)
2. Call it from `build/10-build.sh`
3. Test locally with `just build`
4. Push to trigger GitHub Actions build

### Adding Homebrew Packages
Add packages to `custom/brew/default.Brewfile` or create a new `.Brewfile`.

### Adding ujust Recipes
Add recipes to `custom/ujust/rocinante.just` or create a new `.just` file in `custom/ujust/`. They will be concatenated into `60-custom.just` at build time.

### ujust Recipes
User-level configuration via ujust (defined in `custom/ujust/rocinante.just`):
- `ujust first-run` - Run all first-time setup tasks
- `ujust setup-1password-browser` - Configure 1Password for Flatpak browsers
- `ujust setup-yubikey-ssh` - Configure YubiKey for SSH/git signing (FIDO2)
- `ujust enable-yubikey-gpg` - Prepare shell for GPG operations with YubiKey 5
- `ujust toggle-suspend` - Toggle system suspend for remote access (desktop-aware: GNOME/KDE)
- `ujust configure-yubikey-pam` - Configure YubiKey for PAM authentication (desktop-aware: GDM/SDDM)
- `ujust setup-borgmatic` - Set up borgmatic backups to BorgBase (encrypted, automated)
- `ujust setup-gpu-passthrough` - Configure IOMMU and Incus for GPU passthrough
- `ujust fix-amdgpu` - Apply AMD GPU workarounds for Framework laptops
- `ujust fix-sleep` - Fix sleep/suspend S0ix issues on Framework 13 AMD
- `ujust diagnose-sleep` - Diagnose sleep/suspend issues on Framework 13 AMD

## Pre-commit Checklist

Before committing or opening a PR, verify the following pass:

- **shellcheck**: All `build/*.sh` files must pass shellcheck with no errors
- **just fmt**: `just --fmt --check --unstable` must pass on `Justfile` and all `custom/ujust/*.just` files
- **YAML/TOML/JSON**: All config files must be valid (enforced by pre-commit hooks)
- **Brewfile syntax**: `custom/brew/*.Brewfile` must pass Brewfile syntax validation

Run `pre-commit run --all-files` to check everything locally before pushing.

## Common Tasks

### Debugging Build Failures
```bash
# Check latest build status
gh run list --limit 1

# View build logs
gh run view <run-id> --log

# Search for errors in logs
gh run view <run-id> --log | grep -i error
```

### Testing Changes
1. Make changes to build scripts
2. Commit and push to a feature branch
3. Create PR to trigger test build
4. Merge to main after successful build

## Important Notes

### Immutable System Constraints
- Cannot write to `/usr/local` during build (it's a symlink)
- System modifications must happen at build time
- User configurations should use just recipes or dotfiles

### 1Password SSH Agent
When working with Git, ensure 1Password SSH agent is available:
```bash
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
ssh-add -l  # Should show your keys
```

### Container Registry
Images are published to GitHub Container Registry:
- `ghcr.io/allardvdb/rocinante:latest` (GNOME)
- `ghcr.io/allardvdb/rocinante-nvidia:latest` (GNOME + NVIDIA)
- `ghcr.io/allardvdb/rocinante-aurora:latest` (KDE Plasma)
- Historical tags available (daily builds)
- Signed with Cosign for verification

## Troubleshooting

### Build Failures
- Check `/usr/local` vs `/usr/libexec` paths
- Verify package names in dnf5 commands
- Ensure proper directory creation before file writes

### 1Password Browser Integration
- Run: `ujust setup-1password-browser`
- Restart browser after setup
- Verify: Check 1Password browser extension shows "Connected"

## References

- [Universal Blue Documentation](https://universal-blue.org/)
- [Bluefin Project](https://github.com/ublue-os/bluefin)
- [finpilot Template](https://github.com/projectbluefin/finpilot)
- [Just Task Runner](https://github.com/casey/just)
- [1Password Linux](https://support.1password.com/install-linux/)
