# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

**IMPORTANT: All changes must go through a branch and pull request.**

- Never commit directly to `main` - branch protection is enabled
- Create a feature branch for all changes (even small ones)
- Create a PR for review before merging
- Use descriptive branch names (e.g., `fix-1password-docs`, `add-new-recipe`)

## Repository Overview

This is a custom Universal Blue / Bluefin Linux image that creates a personalized developer workstation based on Fedora Silverblue/Kinoite. The image is built using GitHub Actions and published to GitHub Container Registry (ghcr.io).

**Name**: rocinante (named after the Martian gunship from The Expanse)

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions workflow for building/pushing image
├── build_files/               # Build scripts executed during image creation
│   ├── 1password.sh           # 1Password installation with Flatpak browser integration
│   ├── build.sh              # Main build orchestrator
│   ├── fonts.sh              # Custom font installation
│   ├── github-cli.sh         # GitHub CLI installation
│   ├── homebrew.sh           # Homebrew package manager setup
│   ├── justfile.sh           # Just task runner configuration
│   ├── openvpn.sh           # OpenVPN client installation
│   ├── packages.sh          # System package installation
│   └── ublue-update.sh      # Universal Blue update configuration
├── docs/                     # Documentation
│   ├── 1password-flatpak-fix.md     # Solution for 1Password + Firefox Flatpak
│   └── yubikey-1password-authentication.md  # YubiKey + fingerprint hybrid auth
├── Containerfile            # Container build definition
└── README.md               # Project documentation
```

## Base Image

Built on top of: `ghcr.io/ublue-os/bluefin-dx:stable`
- Bluefin DX provides a developer-focused desktop experience
- Includes VS Code, Docker/Podman, and developer tools
- Based on Fedora Silverblue (immutable/atomic desktop)

## Key Customizations

### 1Password Integration
- Desktop app installed via RPM
- CLI tool (op) installed and configured
- Flatpak browser integration via ujust recipe
- SSH agent integration for Git operations
- Located in: `build_files/1password.sh`

**User Setup**: Run `ujust setup-1password-browser` after installation

### Developer Tools
- GitHub CLI (gh) for repository management
- Homebrew for additional package management
- Custom fonts for terminal/IDE
- OpenVPN client (indicator disabled by default, enable with `ujust toggle-openvpn-indicator`)
- Just task runner for automation

### System Configuration
- Universal Blue update system configured
- Custom package installations via rpm-ostree
- Immutable system patterns (using /usr/libexec, not /usr/local)

## Build System

### GitHub Actions Workflow
- Triggers on: push to main, PRs, daily schedule (10:05 UTC)
- Uses Buildah for container building
- Publishes to: `ghcr.io/allardvdb/rocinante`
- Signs images with Cosign
- Tags: latest, latest.YYYYMMDD, YYYYMMDD

### Building Locally
```bash
# Build the container image
podman build -t rocinante:local .

# Run for testing (not recommended for daily use)
podman run -it --rm rocinante:local bash
```

## Development Patterns

### File Locations in Immutable Systems
- Use `/usr/libexec/` for system executables (not `/usr/local/bin`)
- Use `/usr/lib/` for application files
- Use `/etc/` for system configuration
- Use `/var/` for mutable state

### Adding New Features
1. Create a new script in `build_files/`
2. Add execution in `build_files/build.sh`
3. Test locally with podman build
4. Push to trigger GitHub Actions build

### ujust Recipes
User-level configuration via ujust (located in `system_files/usr/share/ublue-os/just/rocinante.just`):
- `ujust first-run` - Run all first-time setup tasks
- `ujust setup-1password-browser` - Configure 1Password for Flatpak browsers
- `ujust setup-yubikey-ssh` - Configure YubiKey for SSH/git signing (FIDO2)
- `ujust enable-yubikey-gpg` - Prepare shell for GPG operations with YubiKey 5
- `ujust toggle-openvpn-indicator` - Enable/disable OpenVPN tray indicator
- `ujust toggle-suspend` - Toggle system suspend for remote access

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
- Public access: `ghcr.io/allardvdb/rocinante:latest`
- Historical tags available (daily builds)
- Signed with Cosign for verification

## Future Improvements

- Automated Flatpak app installation
- Homebrew package lists
- Dotfiles management

## Troubleshooting

### Build Failures
- Check `/usr/local` vs `/usr/libexec` paths
- Verify package names in rpm-ostree commands
- Ensure proper directory creation before file writes

### 1Password Browser Integration
- Run: `ujust setup-1password-browser`
- Restart browser after setup
- Verify: Check 1Password browser extension shows "Connected"

## References

- [Universal Blue Documentation](https://universal-blue.org/)
- [Bluefin Project](https://github.com/ublue-os/bluefin)
- [Just Task Runner](https://github.com/casey/just)
- [1Password Linux](https://support.1password.com/install-linux/)