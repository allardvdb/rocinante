# AMD GPU Hang on Framework 13 (Strix Point / Radeon 890M)

*Workarounds for the amdgpu MES scheduler hang affecting AMD Ryzen AI 300 series*

## The Problem

The Framework Laptop 13 with AMD Ryzen AI 9 HX 370 (Radeon 890M, "Strix Point", gfx1150) experiences random hard system freezes caused by the `amdgpu` kernel driver. When this happens:

- The screen freezes (mouse cursor may still move but nothing responds to clicks)
- Keyboard input is ignored
- The system is unreachable over the network
- Only a hard power-off recovers the system

This occurs both during normal use and after waking from suspend (s2idle).

## Root Cause

The GPU's MES (Micro Engine Scheduler) stops responding, causing a cascade of failures:

```
amdgpu 0000:c1:00.0: amdgpu: MES failed to respond to msg=MISC (WAIT_REG_MEM)
amdgpu 0000:c1:00.0: amdgpu: failed to reg_write_reg_wait
amdgpu 0000:c1:00.0: amdgpu: MES ring buffer is full.
```

Related errors that may appear before or between hangs:

```
amdgpu 0000:c1:00.0: amdgpu: VPE queue reset failed
amd_pmc AMDI000A:00: Last suspend didn't reach deepest state
```

This is a known upstream bug in the `amdgpu` driver affecting Strix Point GPUs. It is **not** distribution-specific — it affects Bluefin, Bazzite, Fedora, Ubuntu, and Arch alike. AMD is aware and the issue is being tracked on the amd-gfx mailing list.

## Affected Configuration

- **Laptop**: Framework Laptop 13 (AMD Ryzen AI 300 Series)
- **CPU/GPU**: AMD Ryzen AI 9 HX 370 / Radeon 890M
- **GPU IP**: gfx_v11_0 / mes_v11_0 (RDNA 3.5)
- **Kernel**: 6.17.x (known good range; 6.18.x and 6.19.x are **worse**)
- **Firmware**: linux-firmware-20260110

## Workarounds

These are machine-specific kernel parameters, not baked into the rocinante image. The recommended way to apply them is:

```bash
ujust fix-amdgpu
```

This automatically applies the parameters below and prompts for a reboot. For manual control, use `rpm-ostree kargs`:

### Disable Panel Self Refresh (PSR)

Reported to reduce hang frequency, especially for users running sustained workloads:

```bash
rpm-ostree kargs --append="amdgpu.dcdebugmask=0x10"
```

### Disable Scatter/Gather Display

Another display-related mitigation that has helped some users:

```bash
rpm-ostree kargs --append="amdgpu.sg_display=0"
```

### Disable Compute Wave Save/Restore (for compute workloads)

If running GPU compute workloads (Ollama, ROCm, machine learning), this can prevent MES hangs triggered by sustained compute:

```bash
rpm-ostree kargs --append="amdgpu.cwsr_enable=0"
```

### Apply all at once

```bash
rpm-ostree kargs \
  --append="amdgpu.dcdebugmask=0x10" \
  --append="amdgpu.sg_display=0"
```

Reboot after applying. To verify:

```bash
cat /proc/cmdline | tr ' ' '\n' | grep amdgpu
```

To remove a parameter later:

```bash
rpm-ostree kargs --delete="amdgpu.sg_display=0"
```

## Diagnosing Hangs

After a hard reboot, check the previous boot's journal for GPU errors:

```bash
# Check for MES/GPU errors in the previous boot
journalctl -b -1 --priority=0..3 | grep -i amdgpu

# Check for suspend/resume issues
journalctl -b -1 -k | grep -i -E 'suspend|resume|s2idle|MES|VPE'
```

## Kernels to Avoid

Per the Framework community, kernels **6.18.x and 6.19.x** introduce additional amdgpu regressions (broken CWSR causing GPU reset loops). Stick with 6.15.x through 6.17.x until fixes land upstream.

## linux-firmware Regression (20260221)

The `linux-firmware-20260221-1` package introduced a regression that breaks S0ix on Strix Point GPUs. When affected:

- `amd_pmc: Last suspend didn't reach deepest state` appears after every resume
- S0ix entry count and residency are both 0
- Battery drains rapidly during suspend

**Fix:** The rocinante image pins `linux-firmware` to version 20260309+ at build time via `build/50-firmware.sh`. If you're on a stock Fedora install, update firmware manually:

```bash
# Check current version
rpm -q linux-firmware

# If on 20260221, update through dnf or wait for next image rebuild
sudo dnf5 update linux-firmware
```

See: [Bazzite #4356](https://github.com/bazzite-org/bazzite/issues/4356)

## Sleep/Suspend Fixes

Beyond GPU stability, several factors affect sleep quality on Framework 13 AMD:

### S0ix Blockers

| Blocker | Solution | Applied by |
|---------|----------|------------|
| Touchpad (PIXA3854) wakeup events | Disable as wakeup source before suspend | `ujust fix-sleep` |
| Lid sensor wakeup events | Disable as wakeup source before suspend | `ujust fix-sleep` |
| Goodix fingerprint reader (27c6:609c) | Disable via udev rule | Build-time (image) |
| GVFS/FUSE mounts blocking suspend | Lazy-unmount before suspend | Build-time (image) |
| Missing RTC ACPI alarm | `rtc_cmos.use_acpi_alarm=1` kernel param | `ujust fix-sleep` |

### Kernel Version Notes

- **6.18.10**: Has amdgpu VPE suspend regression (queue reset fails on resume)
- **6.18.16+**: VPE fix backported (available in F43 testing)
- **7.0+**: Expected to include MES scheduler improvements for gfx1150

### Diagnostic Commands

```bash
# Run full diagnostics
ujust diagnose-sleep

# Check S0ix stats after resume (non-zero = working)
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats

# Timed suspend test (10 seconds)
sudo rtcwake -m freeze -s 10
```

## References

- [AMD GPU MES Timeouts on Framework 13 (community thread)](https://community.frame.work/t/amd-gpu-mes-timeouts-causing-system-hangs-on-framework-laptop-13-amd-ai-300-series/71364)
- [Critical amdgpu bugs in kernel 6.18/6.19](https://community.frame.work/t/attn-critical-bugs-in-amdgpu-driver-included-with-kernel-6-18-x-6-19-x/79221)
- [MES ring buffer overflow fix (upstream patch)](https://lists.freedesktop.org/archives/amd-gfx/2024-July/111372.html)
- [gfx1150 MES scheduler wedge report (amd-gfx mailing list)](http://www.mail-archive.com/amd-gfx@lists.freedesktop.org/msg133723.html)
- [Bazzite #4356 — linux-firmware S0ix regression](https://github.com/bazzite-org/bazzite/issues/4356)
- [Bluefin #4123 — GVFS blocking suspend](https://github.com/ublue-os/bluefin/issues/4123)
- [Bluefin #3862 — Framework 13 sleep issues](https://github.com/ublue-os/bluefin/issues/3862)
- [Arch Wiki — Framework Laptop 13 Sleep](https://wiki.archlinux.org/title/Framework_Laptop_13#Sleep)
