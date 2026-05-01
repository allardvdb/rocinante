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
# matches exactly the build for ${BASE_KERNEL}.
dnf5 -y install /akmods-src/rpms/kmods/kmod-framework-laptop-*.rpm

# Sanity-check: the installed kmod's version must contain the kernel.
if ! rpm -q kmod-framework-laptop --qf '%{VERSION}\n' | grep -q "${BASE_KERNEL%.x86_64}"; then
    echo "ERROR: installed kmod-framework-laptop does not match BASE_KERNEL=${BASE_KERNEL}"
    rpm -q kmod-framework-laptop --qf 'installed: %{NVR}\n'
    exit 1
fi
echo "Installed kmod-framework-laptop matching ${BASE_KERNEL}"

echo "::endgroup::"
