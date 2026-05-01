#!/usr/bin/bash
set -eoux pipefail

# Install kmod-framework-laptop from the akmods bind mount, version-matched
# to whatever kernel ${BASE_IMAGE} ships. This is intentionally minimal:
# - does NOT erase or replace the kernel (avoids the switch_root / ostree
#   dracut module bug that bricked latest.20260419)
# - does NOT regenerate the initramfs
# - does NOT install kernel-coupled packages other than the kmod itself
#
# Inputs (set by Containerfile RUN):
#   BASE_KERNEL  — uname -r style version, e.g. 6.19.12-200.fc43.x86_64
#   /akmods-src  — bind mount of ghcr.io/ublue-os/akmods:coreos-stable-43-${BASE_KERNEL}

echo "::group:: Install framework-laptop kmod from akmods bind mount"

if [[ -z "${BASE_KERNEL:-}" ]]; then
    echo "ERROR: BASE_KERNEL is unset — workflow must pass it as a build-arg"
    exit 1
fi
if [[ ! -d /akmods-src/rpms ]]; then
    echo "ERROR: /akmods-src is not bind-mounted — Containerfile is misconfigured"
    exit 1
fi

# ublue-os-akmods-addons ships the COPR repo config that supplies
# framework-laptop-kmod-common as a dependency. Bluefin:stable already has
# this repo enabled, but aurora:stable does not — install unconditionally.
dnf5 -y install /akmods-src/rpms/ublue-os/ublue-os-akmods-addons-*.rpm

# Install the kmod for the running kernel. The akmods image's RPM filenames
# encode the kernel version, so a glob across kmod-framework-laptop-*
# matches exactly the build for ${BASE_KERNEL}. dnf5 fails loud if the
# glob is empty or the install conflicts.
#
# Note: bluefin:stable already ships kmod-framework-laptop, so dnf5 will
# report "already installed" on rocinante / rocinante-nvidia and proceed
# silently. aurora:stable does not, and dnf5 will install it freshly. Both
# paths are intentional.
dnf5 -y install /akmods-src/rpms/kmods/kmod-framework-laptop-*.rpm

# Sanity-check: confirm the package is present after the install. The
# kmod's RPM metadata does NOT encode the kernel version in the Name or
# Version fields (only in the .rpm filename), so a stricter version
# match would be misleading; rely instead on the bind-mount tag being
# coreos-stable-43-${BASE_KERNEL} for kernel correctness.
if ! rpm -q kmod-framework-laptop > /dev/null 2>&1; then
    echo "ERROR: kmod-framework-laptop is not installed after dnf5"
    exit 1
fi
echo "kmod-framework-laptop present: $(rpm -q kmod-framework-laptop --qf '%{NVR}.%{ARCH}\n')"

echo "::endgroup::"
