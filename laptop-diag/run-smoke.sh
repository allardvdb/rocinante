#!/usr/bin/bash
# Post-rebase diagnostics + smoke test for rocinante on Framework 13 AMD.
# Run on the laptop after `rpm-ostree rebase ...:latest` and reboot.
# Writes ./smoke-followup.txt next to this script. Pass that file back.

set -u
out="$(cd "$(dirname "$0")" && pwd)/smoke-followup.txt"
exec > >(tee "$out") 2>&1

section() { echo; echo "=== $* ==="; }

echo "rocinante laptop diagnostics — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "(cache sudo so the rtcwake step doesn't block on a password prompt)"
sudo -v

section "uname -r"
uname -r

section "bootc status"
sudo bootc status

section "systemctl --failed"
systemctl --failed --no-pager

section "journalctl -u systemd-remount-fs.service -u systemd-sysusers.service -b"
journalctl -u systemd-remount-fs.service -u systemd-sysusers.service -b --no-pager

section "Sysusers files declaring incus / incus-admin groups"
grep -RnH '^g incus' /usr/lib/sysusers.d/ /etc/sysusers.d/ 2>/dev/null || echo "(no matches)"

section "MES check (kernel-pin removal exit criterion 3)"
if journalctl -k -b | grep -i 'MES failed to respond' > /dev/null; then
    echo "BAD: MES errors present in this boot"
    journalctl -k -b | grep -i 'MES failed to respond' | head -5
else
    echo "CLEAN: no MES errors in this boot"
fi

section "journalctl priority<=3 this boot (last 60 lines)"
journalctl -p 3 -b --no-pager | tail -60

section "rpm-ostree kargs"
rpm-ostree kargs 2>/dev/null || true

section "rpm -qa: kernel / incus / framework-laptop"
rpm -qa | grep -E '^(kernel|incus|framework-laptop)' | sort

section "Suspend / S0ix test (30s rtcwake freeze)"
echo "Pre-suspend S0ix stats:"
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats 2>/dev/null || echo "(s0ix_stats not readable)"
echo
echo "Suspending for 30s..."
sudo rtcwake -m freeze -s 30 || echo "(rtcwake failed; continuing)"
echo "Resumed at $(date -u +%H:%M:%SZ)"
echo "Post-suspend S0ix stats:"
sudo cat /sys/kernel/debug/amd_pmc/s0ix_stats 2>/dev/null || echo "(s0ix_stats not readable)"
echo
echo "Post-suspend errors (priority<=3, last 60s):"
journalctl -p 3 --since='60 sec ago' --no-pager

section "Done"
echo "Output written to: $out"
