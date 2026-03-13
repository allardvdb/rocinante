---
name: rocinante-system
description: Running-system guidance for AI agents on a deployed rocinante (Fedora Atomic / Universal Blue / Bluefin) desktop. Use when helping install software, configure services, or modify the system.
trigger: Any request to install, configure, or modify system packages/services on the running system
---

# Rocinante System — Runtime Agent Guidance

This document describes how to correctly help users on a deployed rocinante system. Rocinante is a custom
Universal Blue / Bluefin image built on Fedora Atomic Desktop. It has an immutable root filesystem and
follows OCI-based update semantics. Many conventional Linux operations do not apply here.

---

## Critical Rules (Hard Stops)

The following commands will either fail silently, produce errors, or produce changes that are lost on the
next system update. Agents MUST NOT suggest them:

- **NEVER** run `dnf install`, `dnf5 install`, or `yum install` on the running system — the root
  filesystem is immutable and these will fail or have no lasting effect.
- **NEVER** run `rpm-ostree install` or `rpm-ostree override` to layer packages — this image uses
  bootc/OCI-based updates, not rpm-ostree package layering. Layered packages are not supported and
  may conflict with the image.
- **NEVER** write to `/usr/` and expect the changes to persist — it is read-only at runtime as an
  OCI image layer.
- **NEVER** suggest rebooting into a new deployment as a way to "install" software at runtime — the
  user needs a proper image build change, not a reboot workaround.

---

## System Architecture

### How Rocinante Works

Rocinante is a custom Universal Blue / Bluefin image built on Fedora Atomic Desktop (Silverblue for
GNOME, Kinoite for KDE Plasma). The key architectural properties are:

- The root filesystem (`/usr/`) is an **immutable OCI image layer**, mounted read-only at runtime.
- System changes happen at **image build time** via the `Containerfile` and build scripts in `build/`.
- Updates arrive as **new OCI image pulls**, not package-by-package installs.
- The running system is a snapshot; nothing written to `/usr/` at runtime survives an image update.

The image is built by GitHub Actions, published to GitHub Container Registry (`ghcr.io/allardvdb/rocinante`),
and applied on the next system update via `bootc upgrade`.

### Mutable vs Immutable Paths

| Path | Mutable? | Notes |
|------|----------|-------|
| `/usr/` | No | OCI image layer, read-only at runtime |
| `/etc/` | Yes | System configuration (writable overlay, persists) |
| `/var/` | Yes | Persistent mutable state |
| `~/.config/` | Yes | User configuration |
| `~/.local/` | Yes | User data and binaries |
| Homebrew prefix | Yes | Managed by `brew-setup.service`, survives updates |
| Flatpak apps | Yes | User or system Flatpak installs persist across updates |

---

## Software Installation Decision Framework

Use this decision tree to determine the correct installation method for any given software:

### CLI tool or development dependency

Use Homebrew:

```bash
brew install <package>
```

For the install to survive image rebuilds automatically, add it to the repo:

```
custom/brew/default.Brewfile
```

### GUI desktop application

Use Flatpak from Flathub:

```bash
flatpak install flathub <app-id>
```

Flatpak installs are stored in `/var/` (system) or `~/.local/share/flatpak/` (user) and persist
across image updates.

### System-level integration

For anything requiring systemd units, PAM modules, kernel modules, udev rules, or other changes to
`/usr/`:

**This requires an image build change.** Modify the appropriate build scripts in the repository,
open a PR, and let the image rebuild. See [When Runtime Won't Work](#when-runtime-wont-work-build-change-workflow)
below.

### User-level configuration

Dotfiles, shell configuration, desktop settings:

- Edit `~/.config/` directly, or
- Use a `ujust` recipe if one exists for the task

### One-off or experimental tool

Use a mutable container environment:

```bash
distrobox create --name mybox --image fedora:latest
distrobox enter mybox
# now you can dnf install freely inside the container
```

Or with toolbox:

```bash
toolbox create
toolbox enter
```

### Kernel parameters

The only legitimate runtime use of rpm-ostree on this image:

```bash
rpm-ostree kargs --append=KEY=VALUE
```

---

## Safe Runtime Operations

The following operations are safe to perform directly on the running system:

### Homebrew

```bash
brew install <package>
brew uninstall <package>
brew upgrade
```

Homebrew manages its own prefix and persists across image updates.

### Flatpak

```bash
flatpak install flathub <app-id>
flatpak uninstall <app-id>
flatpak update
```

Both `--user` (default) and system scope work. User installs go to `~/.local/share/flatpak/`.

### File edits

- Edit any file under `~/.config/`, `~/.local/`, or `~/` directly.
- Edit `/etc/` files for system-level configuration (changes persist via the writable overlay).

### User systemd units

```bash
systemctl --user enable <unit>
systemctl --user start <unit>
systemctl --user stop <unit>
systemctl --user status <unit>
```

### System systemd units (that already exist in the image)

```bash
sudo systemctl enable <unit>
sudo systemctl start <unit>
sudo systemctl stop <unit>
```

Note: you can only enable/start units that were installed into the image at build time.

### ujust recipes

```bash
ujust <recipe>
```

See the [ujust Recipe Reference](#ujust-recipe-reference) section for available recipes.

### Container workloads

```bash
distrobox create --name <name> --image <image>
distrobox enter <name>
podman run <image>
```

---

## When Runtime Won't Work: Build Change Workflow

If the user needs something that requires modifying `/usr/` — a new system package, udev rule,
systemd unit installed into the image, PAM configuration, or kernel module — the correct approach
is to modify the image source and trigger a rebuild.

### Where to add things

| Change type | Location in repo |
|-------------|-----------------|
| System packages (dnf5) | `build/10-build.sh` (add to the dnf5 install line) or a new numbered script |
| Homebrew packages | `custom/brew/default.Brewfile` |
| ujust recipes | `custom/ujust/rocinante.just` or a new `.just` file in `custom/ujust/` |
| Udev rules | `custom/udev/` directory |
| Systemd sleep hooks | `custom/systemd/system-sleep/` directory |
| System executables | Place in `/usr/libexec/` — NEVER `/usr/local/bin/` (it is a symlink) |

### How the build works (ctx-stage pattern)

Files in `build/` and `custom/` are mounted read-only at `/ctx` during the container build. They
are NOT copied into the final image. The main build script `build/10-build.sh` reads from `/ctx`
at build time to install packages, configure units, and concatenate ujust recipes.

This means: to change the running system persistently, change the source files in the repo, not
the running system.

### Branch + PR workflow

1. Create a feature branch in the repository.
2. Make the necessary changes to build scripts or custom files.
3. Open a pull request — this triggers a test build via GitHub Actions.
4. Merge after the build succeeds.
5. The new image is built automatically on merge.
6. The user receives the change on next system update (`bootc upgrade` or automatic update).

```bash
# Example workflow
git checkout -b add-<feature>
# ... make changes ...
git push -u origin add-<feature>
gh pr create
```

---

## ujust Recipe Reference

These recipes are available on the running system via `ujust <recipe>`:

| Recipe | Description |
|--------|-------------|
| `ujust first-run` | Run all first-time setup tasks |
| `ujust setup-1password-browser` | Configure 1Password for Flatpak browsers |
| `ujust setup-yubikey-ssh` | Configure YubiKey for SSH/git signing (FIDO2) |
| `ujust enable-yubikey-gpg` | Prepare shell for GPG operations with YubiKey 5 |
| `ujust toggle-suspend` | Toggle system suspend for remote access |
| `ujust configure-yubikey-pam` | Configure YubiKey for PAM authentication |
| `ujust setup-borgmatic` | Set up borgmatic backups to BorgBase |
| `ujust setup-gpu-passthrough` | Configure IOMMU and Incus for GPU passthrough |
| `ujust fix-amdgpu` | Apply AMD GPU workarounds for Framework laptops |
| `ujust fix-sleep` | Fix sleep/suspend S0ix issues on Framework 13 AMD |
| `ujust diagnose-sleep` | Diagnose sleep/suspend issues on Framework 13 AMD |

---

## Legitimate rpm-ostree Uses

On this image, rpm-ostree is present but its package management commands are NOT supported. The
only valid use is managing kernel boot parameters:

```bash
# Add a kernel parameter
rpm-ostree kargs --append=KEY=VALUE

# Remove a kernel parameter
rpm-ostree kargs --delete=KEY=VALUE

# List current kernel parameters
rpm-ostree kargs
```

All other rpm-ostree subcommands (`install`, `uninstall`, `override replace`, `override remove`,
`reset`) are NOT supported on this image and must not be suggested.
