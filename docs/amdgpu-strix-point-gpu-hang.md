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

These are machine-specific kernel parameters, not baked into the rocinante image. Apply them on the affected machine with `rpm-ostree kargs`:

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

## References

- [AMD GPU MES Timeouts on Framework 13 (community thread)](https://community.frame.work/t/amd-gpu-mes-timeouts-causing-system-hangs-on-framework-laptop-13-amd-ai-300-series/71364)
- [Critical amdgpu bugs in kernel 6.18/6.19](https://community.frame.work/t/attn-critical-bugs-in-amdgpu-driver-included-with-kernel-6-18-x-6-19-x/79221)
- [MES ring buffer overflow fix (upstream patch)](https://lists.freedesktop.org/archives/amd-gfx/2024-July/111372.html)
- [gfx1150 MES scheduler wedge report (amd-gfx mailing list)](http://www.mail-archive.com/amd-gfx@lists.freedesktop.org/msg133723.html)
