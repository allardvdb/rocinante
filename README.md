# rocinante

Custom [Universal Blue](https://universal-blue.org/) image based on Bluefin-DX with personal customizations.

## Base Image

Built on: `ghcr.io/ublue-os/bluefin-dx:stable`

## Customizations

This image includes the following modifications to the base Bluefin-DX:

### Software Additions
- **1Password** - Password manager with automatic Flatpak browser integration
- **OpenVPN3** - VPN client with indicator and SELinux workarounds
- **tmux** - Terminal multiplexer

### System Configurations
- **Podman socket** - Enabled by default for container operations
- **PCSCD socket** - Disabled to avoid conflicts with YubiKey

### Integrations
- **1Password + Firefox Flatpak** - Pre-configured native messaging integration (see [docs/1password-flatpak-fix.md](docs/1password-flatpak-fix.md))
- **YubiKey Support** - Full GPG/SSH integration for YubiKey devices

## Documentation

### Custom Features
- [1Password + Firefox Flatpak Integration](docs/1password-flatpak-fix.md) - Solution for connecting 1Password desktop with Flatpak browsers
- [YubiKey + Fingerprint Authentication](docs/yubikey-1password-authentication.md) - Hybrid authentication setup using YubiKey 5 with laptop fingerprint scanner

### Upstream Documentation
- [Universal Blue Documentation](https://universal-blue.org/)
- [Bluefin Documentation](https://projectbluefin.io/)
- [Image Building Guide](https://blue-build.org/learn/)

## Building

```bash
# Build the image locally
just build

# Build ISO for installation
just build-iso
```

## Installation

```bash
# Switch existing system to this image
sudo bootc switch ghcr.io/<your-github-username>/rocinante

# Or use the ISO for fresh installation
# Build ISO first with: just build-iso
```

## Repository Structure

```
rocinante/
├── Containerfile           # Image definition
├── build_files/
│   ├── build.sh           # Main build script
│   ├── 1password.sh       # 1Password installation with Flatpak integration
│   ├── openvpn.sh         # OpenVPN setup
│   └── devops.sh          # DevOps tools installation
├── docs/                  # Custom documentation
│   ├── 1password-flatpak-fix.md
│   └── yubikey-1password-authentication.md
└── system_files/          # System configuration files
```

## Contributing

This is a personal configuration, but feel free to fork and adapt for your own needs.

## Support

For issues specific to:
- **This image**: Open an issue in this repository
- **Universal Blue/Bluefin**: [Universal Blue Forums](https://universal-blue.discourse.group/) or [Discord](https://discord.gg/WEu6BdFEtp)
- **Image building**: [Blue Build Documentation](https://blue-build.org/)

## License

See LICENSE file for details.