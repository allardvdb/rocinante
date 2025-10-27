# YubiKey 5 + Fingerprint Hybrid Authentication for 1Password on Linux

*A practical approach using YubiKey 5 with laptop fingerprint scanner for 1Password system authentication*

## Overview

Instead of using YubiKey Bio (limited to FIDO2), this setup uses:
- **YubiKey 5** - Full feature set (GPG, PIV, OpenPGP, FIDO2, OTP, etc.)
- **Laptop fingerprint scanner** - For convenient biometric unlocking
- **PAM configuration** - Chains both authentication methods

This provides the best of both worlds: full YubiKey functionality + convenient biometric unlocking.

## Why This Approach?

### YubiKey 5 Advantages over Bio
- Full GPG/OpenPGP support for git signing, SSH keys
- PIV for smart card authentication
- OTP support
- NFC capability for mobile use
- ~$55 vs $85 for Bio model
- More versatile for other security needs

### Combined with Laptop Fingerprint
- Use existing hardware (no additional cost)
- Fingerprint for quick unlocks
- YubiKey for high-security operations
- Flexible PAM configuration options

## Setup Instructions

### 1. Prerequisites

```bash
# Fedora/Bluefin packages
sudo dnf install -y \
    pam-u2f \
    fprintd \
    fprintd-pam \
    yubikey-manager \
    yubikey-manager-qt
```

### 2. Configure Fingerprint Scanner

```bash
# Enroll fingerprints
fprintd-enroll

# Test fingerprint authentication
fprintd-verify

# Enable fingerprint for system auth
sudo authselect enable-feature with-fingerprint
sudo authselect apply-changes
```

### 3. Register YubiKey 5 for FIDO2/U2F

```bash
# Create Yubico config directory
mkdir -p ~/.config/Yubico

# Register YubiKey (touch it when it blinks)
pamu2fcfg -o pam://$(hostname) -i pam://$(hostname) > ~/.config/Yubico/u2f_keys

# For additional keys or backup keys, append:
pamu2fcfg -o pam://$(hostname) -i pam://$(hostname) -n >> ~/.config/Yubico/u2f_keys
```

### 4. Configure PAM for 1Password System Authentication

Edit `/etc/pam.d/polkit-1` to create a flexible authentication chain:

```bash
sudo nano /etc/pam.d/polkit-1
```

Add at the top (order matters):

```pam
#%PAM-1.0
# Hybrid authentication: fingerprint OR YubiKey OR password

# Try fingerprint first (quick and convenient)
auth sufficient pam_fprintd.so

# Try YubiKey if present (for when fingerprint fails or preference)
auth sufficient pam_u2f.so cue nouserok

# Fall back to password
auth include system-auth
```

### 5. Enable 1Password System Authentication

1. Open 1Password
2. Go to **Settings → Security**
3. Enable **"Unlock using system authentication service"**
4. Set **"Require system authentication after system is idle"** to your preference (e.g., 12 hours)
5. Lock and unlock 1Password to test

## Usage Scenarios

### Daily Workflow

**After reboot:**
1. 1Password prompts for system authentication
2. Touch fingerprint scanner (fastest)
3. OR insert YubiKey and touch it
4. OR type system password (fallback)

**During the day:**
- 1Password stays unlocked within idle timeout
- After timeout: Quick fingerprint touch to unlock

**High-security operations:**
- Remove YubiKey = additional protection
- Can require YubiKey for specific operations via PAM service files

### Advanced Configuration Options

#### Option A: Require BOTH Fingerprint AND YubiKey
```pam
# Super secure: both required
auth required pam_fprintd.so
auth required pam_u2f.so
```

#### Option B: Fingerprint for 1Password, YubiKey for sudo
Create separate PAM configurations:

`/etc/pam.d/polkit-1` (for 1Password):
```pam
auth sufficient pam_fprintd.so
auth include system-auth
```

`/etc/pam.d/sudo` (for terminal):
```pam
auth required pam_u2f.so
auth include system-auth
```

#### Option C: Time-based Requirements
Use PAM time module to require stronger auth during off-hours:
```pam
auth [success=ignore default=1] pam_time.so
auth required pam_u2f.so
auth sufficient pam_fprintd.so
auth include system-auth
```

## YubiKey 5 Bonus Features

Since you have the full YubiKey 5, also configure:

### GPG for Git Signing
```bash
gpg --card-edit
# Set up GPG keys on YubiKey
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true
```

### SSH via GPG
```bash
# Add to ~/.bashrc
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent
```

### PIV for System Login
```bash
# Configure PIV slot for system authentication
ykman piv generate-key --algorithm RSA2048 9a pubkey.pem
ykman piv generate-certificate --subject "CN=Your Name" 9a pubkey.pem
```

## Troubleshooting

### Fingerprint Not Working
```bash
# Check fprintd service
systemctl status fprintd.service

# Re-enroll fingerprints
fprintd-delete $USER
fprintd-enroll
```

### YubiKey Not Detected
```bash
# Check YubiKey presence
ykman info

# Verify U2F registration
cat ~/.config/Yubico/u2f_keys
```

### 1Password Not Using System Auth
```bash
# Check polkit policy exists
ls -la /usr/share/polkit-1/actions/com.1password.1Password.policy

# Test polkit authentication
pkcheck --action-id com.1password.1Password.unlock --process $$
```

## Security Considerations

1. **Fingerprints are convenience, not high security** - Use for quick unlocks, not critical operations
2. **YubiKey provides strong 2FA** - Physical possession required
3. **Layered approach** - Different authentication for different sensitivity levels
4. **Backup methods** - Always have password as fallback

## Limitations

- **No persistence across reboots** - Linux 1Password design limitation
- **In-memory secrets only** - Cleared on 1Password restart
- **Not like macOS** - Won't remember for 14 days
- **Physical presence required** - For both fingerprint and YubiKey

## Conclusion

This hybrid approach provides:
- ✅ Quick biometric unlocking via laptop fingerprint
- ✅ Full YubiKey 5 features for other security needs
- ✅ Flexible security levels via PAM configuration
- ✅ Cost-effective (uses existing fingerprint + cheaper YubiKey 5)

While it doesn't match macOS's 14-day persistence, it significantly reduces password typing while maintaining security.

## References

- [1Password System Authentication for Linux](https://support.1password.com/system-authentication-linux/)
- [Yubico PAM-U2F Module](https://developers.yubico.com/pam-u2f/)
- [Fedora Fingerprint Authentication](https://docs.fedoraproject.org/en-US/quick-docs/fingerprint-authentication/)
- [YubiKey 5 Documentation](https://docs.yubico.com/hardware/yubikey/yk-5/)

---

*Last updated: October 2025*
*Tested on: Bluefin Linux (Fedora 40 base)*