# Sleep/Suspend Setup Guide (Framework 13 AMD)

*How to activate the S0ix deep sleep fixes on a Framework 13 with AMD Ryzen AI 300 (Strix Point)*

## Prerequisites

Merge the sleep/suspend PRs and wait for a successful image build, or build locally with `just build`.

## Step 1: Rebase to the new image

```bash
# Check that the latest build succeeded
gh run list --limit 1

# Upgrade to the new image
sudo bootc upgrade
systemctl reboot
```

## Step 2: Apply machine-specific fixes

After rebooting onto the new image:

```bash
# Interactively configure sleep fixes (RTC alarm, ASPM policy, wakeup sources)
ujust fix-sleep

# Interactively configure GPU fixes (PSR, scatter/gather)
ujust fix-amdgpu
```

Both recipes show current status and let you toggle individual fixes. They prompt for a reboot if kernel parameters were changed.

## Step 3: Verify

After the final reboot:

```bash
ujust diagnose-sleep
```

Check the output for:
- `linux-firmware` shows `20260309` or newer
- `rtc_cmos.use_acpi_alarm=1` is set (if enabled via fix-sleep)
- PCIe ASPM policy matches your selection (if set via fix-sleep)
- Wakeup source hook is listed under installed sleep hooks (if enabled via fix-sleep)
- No known-bad firmware warning

Then run a timed suspend test:

```bash
sudo rtcwake -m freeze -s 10
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats
```

Non-zero **Success** count and **Residency** values mean S0ix deep sleep is working. If both are 0, see Troubleshooting below.

## What's applied automatically vs manually

### Automatic (baked into the image)

| Fix | Mechanism | File |
|-----|-----------|------|
| linux-firmware pinned to 20260309+ | Koji RPM override at build time | `build/50-firmware.sh` |
| Goodix fingerprint reader (27c6:609c) disabled | Udev rule deauthorizes USB device | `custom/udev/99-disable-goodix-fingerprint.rules` |
| GVFS/FUSE mounts unmounted before suspend | systemd-sleep hook with lazy unmount | `custom/systemd/system-sleep/50-unmount-fuse.sh` |

### Manual (machine-specific, via ujust)

| Fix | Command | What it does |
|-----|---------|-------------|
| RTC ACPI alarm for s2idle | `ujust fix-sleep` | Toggle `rtc_cmos.use_acpi_alarm=1` kernel param |
| PCIe ASPM policy | `ujust fix-sleep` | Select ASPM policy (default/performance/powersave/powersupersave/unset) |
| Touchpad/lid wakeup suppression | `ujust fix-sleep` | Toggle sleep hook in `/etc/systemd/system-sleep/` |
| PSR disable (dcdebugmask) | `ujust fix-amdgpu` | Toggle `amdgpu.dcdebugmask=0x10` kernel param |
| Scatter/gather disable | `ujust fix-amdgpu` | Toggle `amdgpu.sg_display=0` kernel param |

## Troubleshooting

### S0ix stats show all zeros

```bash
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats
```

If Success and Residency are both 0 after a suspend:

1. **Check firmware version** — `rpm -q linux-firmware`. If it shows `20260221`, the firmware override did not take effect. Rebuild the image.
2. **Check wakeup sources** — `ujust diagnose-sleep` shows enabled ACPI and USB wakeup sources. Any unexpected device could be blocking S0ix.
3. **Check journal** — `journalctl -b -k | grep -i "amd_pmc\|s0ix\|suspend"` for errors.

### "Last suspend didn't reach deepest state"

This message from `amd_pmc` means S0ix entry failed. Most common causes:

- Bad firmware (20260221 regression) — fixed by image rebuild
- Touchpad wakeup events — fixed by `ujust fix-sleep`
- USB device keeping bus awake — check `ujust diagnose-sleep` USB wakeup section

### Screen doesn't wake after resume

This is the amdgpu VPE suspend regression in kernel 6.18.10. Fixed in 6.18.16+ (available in F43 testing). Will arrive via normal image rebuilds once Fedora promotes the kernel.

### debugfs not accessible

```bash
sudo mount -t debugfs debugfs /sys/kernel/debug
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats
```

## References

- [Sleep/Suspend fixes in amdgpu doc](amdgpu-strix-point-gpu-hang.md#sleepsuspend-fixes)
- [Bazzite #4356 — linux-firmware S0ix regression](https://github.com/bazzite-org/bazzite/issues/4356)
- [Arch Wiki — Framework Laptop 13 Sleep](https://wiki.archlinux.org/title/Framework_Laptop_13#Sleep)

## Hibernate (suspend-then-hibernate)

Suspend-then-hibernate provides macOS-style sleep: the system suspends to RAM for
a configurable delay (default 30 minutes), then hibernates to disk for zero battery
drain. Waking within the delay window is instant; after hibernation, wake takes ~15
seconds and requires the LUKS password.

### Prerequisites

- **Secure Boot must be disabled** in BIOS — kernel lockdown prevents hibernation
- Run `ujust toggle-suspend` if suspend is currently disabled

### Setup

```bash
ujust setup-hibernate
```

This configures:
- Btrfs swap subvolume + swapfile (sized to RAM) at `/var/swap/swapfile`
- Kernel boot parameters (`resume=`, `resume_offset=`)
- Dracut resume module in initramfs
- systemd sleep.conf (30 minute suspend-then-hibernate delay)
- logind lid close → suspend-then-hibernate

A reboot is required after setup.

### Change hibernate delay

Use the fix-sleep menu to adjust the delay:

```bash
ujust fix-sleep
# → Select "Change hibernate delay"
# → Choose: 15min, 30min, 1h, 2h, 3h
```

No reboot required — takes effect on next suspend.

### Removal

```bash
ujust remove-hibernate
```

Removes all hibernate configuration (swap, kernel args, initramfs, configs).

### Known issues

- **Slower system updates**: `rpm-ostree initramfs --enable` rebuilds initramfs on each update
- **LUKS password on wake**: After hibernation, you must enter your disk encryption password
- **SELinux**: The setup script labels the swapfile correctly, but if you encounter AVC denials, run:
  ```bash
  sudo ausearch -m avc -ts recent | audit2allow -M systemd_hibernate
  sudo semodule -i systemd_hibernate.pp
  ```
