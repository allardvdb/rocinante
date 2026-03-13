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
# Apply sleep kernel params + wakeup source hook
ujust fix-sleep

# Re-run fix-amdgpu to pick up the pcie_aspm.policy=powersupersave param
ujust fix-amdgpu
```

Both recipes prompt for a reboot. You can decline the first and reboot after the second.

## Step 3: Verify

After the final reboot:

```bash
ujust diagnose-sleep
```

Check the output for:
- `linux-firmware` shows `20260309` or newer
- `rtc_cmos.use_acpi_alarm=1` is set
- `pcie_aspm.policy=powersupersave` is set
- Wakeup source hook is listed under installed sleep hooks
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
| RTC ACPI alarm for s2idle | `ujust fix-sleep` | Appends `rtc_cmos.use_acpi_alarm=1` kernel param |
| Touchpad/lid wakeup suppression | `ujust fix-sleep` | Installs sleep hook in `/etc/systemd/system-sleep/` |
| PCIe ASPM powersupersave | `ujust fix-amdgpu` | Appends `pcie_aspm.policy=powersupersave` kernel param |

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
