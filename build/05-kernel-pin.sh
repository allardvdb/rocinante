#!/usr/bin/bash
set -eoux pipefail

# Pin the kernel to a known-good version to avoid the amdgpu MES scheduler
# hang on Strix Point (Framework 13 AMD). See docs/amdgpu-strix-point-gpu-hang.md.
#
# Mechanism is a close port of bluefin's build_files/base/03-install-kernel-akmods.sh
# from PR ublue-os/bluefin#4187 (Feb 2026). Differences:
#   - Rocinante is downstream of bluefin:stable, so the swap happens in our
#     own build rather than in bluefin's.
#   - Kernel + kmod RPMs arrive via --mount=type=bind,from=<akmods-stage>
#     (configured in the Containerfile), which is cheaper than the skopeo-copy-
#     then-tar-extract dance bluefin uses inside their script.
#   - Nvidia-open and ZFS kmods come from their own akmods-<variant> images
#     (plain akmods only has common kmods).
#
# Exit criterion: remove this script and revert the Containerfile when
# kernel 7.0+ lands in Fedora stable (expected MES scheduler improvements
# for gfx1150) OR when upstream bluefin re-pins via PR #4187's mechanism.
# See docs/amdgpu-strix-point-gpu-hang.md for current status.

KERNEL_PIN="${KERNEL_PIN:?KERNEL_PIN must be set by the Containerfile}"
BASE_IMAGE="${BASE_IMAGE:-}"

# Bind-mounted by the Containerfile RUN step
AKMODS_SRC=/akmods-src
AKMODS_ZFS_SRC=/akmods-zfs-src
AKMODS_NVIDIA_SRC=/akmods-nvidia-open-src

echo "::group:: Pin kernel to ${KERNEL_PIN}"

# Sanity check: the akmods bind mount must contain the kernel RPMs we need.
# If this fires, the Containerfile's multi-stage tag probably doesn't match
# KERNEL_PIN, or the upstream akmods image layout has changed.
if [[ ! -f "${AKMODS_SRC}/kernel-rpms/kernel-core-${KERNEL_PIN}.rpm" ]]; then
    echo "ERROR: ${AKMODS_SRC}/kernel-rpms/kernel-core-${KERNEL_PIN}.rpm not found"
    echo "Contents of ${AKMODS_SRC}:"
    ls -la "${AKMODS_SRC}" || true
    ls -la "${AKMODS_SRC}/kernel-rpms" || true
    exit 1
fi

# Discover currently installed kernel-version-tied packages.
# kernel-headers, kernel-tools, kernel-tools-libs are userspace and may
# lag the running kernel on upstream — don't touch them.
mapfile -t OLD_KERNEL_PKGS < <(
    rpm -qa --qf '%{NAME}\n' \
        kernel \
        kernel-core \
        kernel-modules \
        kernel-modules-core \
        kernel-modules-extra \
        kernel-devel \
        kernel-devel-matched 2>/dev/null | sort -u
)
echo "Installed kernel packages to erase:"
printf '  %s\n' "${OLD_KERNEL_PKGS[@]}"

# Discover currently installed kmod-* packages that are kernel-version-tied.
# Exclude the plain 'kmod' and 'kmod-libs' userspace tools.
mapfile -t OLD_KMODS < <(
    rpm -qa --qf '%{NAME}\n' 'kmod-*' 2>/dev/null \
        | grep -vE '^(kmod|kmod-libs)$' \
        | sort -u
)
echo "Installed kmods to erase:"
printf '  %s\n' "${OLD_KMODS[@]}"

# Discover currently installed ZFS userspace packages. These must be
# swapped as a set together with kmod-zfs: the akmods-zfs container is
# a snapshot bundled with the pinned kernel, so the ZFS version inside
# it may differ from whatever the base image currently has (e.g.
# akmods-zfs for 6.17.12 ships ZFS 2.3.5, but bluefin:stable has since
# upgraded to 2.3.6). If we leave the old userspace in place, dnf5
# fails to resolve the transaction with "cannot install both
# libnvpair3-<old> and libnvpair3-<new>" style conflicts.
mapfile -t OLD_ZFS < <(
    rpm -qa --qf '%{NAME}\n' \
        'zfs' 'zfs-dracut' 'zfs-test' \
        'libnvpair*' 'libuutil*' 'libzfs*' 'libzpool*' \
        'python3-pyzfs' 2>/dev/null | sort -u
)
echo "Installed ZFS userspace packages to erase:"
printf '  %s\n' "${OLD_ZFS[@]}"

# Erase the old kernel (--nodeps because kmods still depend on it; we'll
# reinstall matching versions in a moment).
if [[ ${#OLD_KERNEL_PKGS[@]} -gt 0 ]]; then
    rpm --erase --nodeps "${OLD_KERNEL_PKGS[@]}"
fi

# Erase the old kmods (--nodeps in case anything in the base image Requires
# them; versions are about to be replaced).
if [[ ${#OLD_KMODS[@]} -gt 0 ]]; then
    rpm --erase --nodeps "${OLD_KMODS[@]}" || true
fi

# Erase the old ZFS userspace so the matching 2.x versions from
# akmods-zfs can install cleanly.
if [[ ${#OLD_ZFS[@]} -gt 0 ]]; then
    rpm --erase --nodeps "${OLD_ZFS[@]}" || true
fi

# Clear stale module trees left behind by the erased packages.
rm -rf /usr/lib/modules/*

# Move every kernel-install.d plugin aside for the duration of the
# dnf5 transaction. The kernel-core and kernel-modules %posttrans
# scriptlets run /usr/bin/kernel-install, which invokes each
# executable plugin under /usr/lib/kernel/install.d/. In a buildah
# container build environment several of those plugins fail loudly
# and take the transaction with them:
#
#   - 05-rpmostree.install  -> tries to run rpm-ostree + dracut to
#     regenerate the initramfs; dracut fails with "Invalid cross-
#     device link" inside the overlayfs build mount
#   - 20-grub.install       -> grub2-probe can't canonicalise 'overlay',
#     grub2-editenv can't write /boot/grub2/grubenv.new
#   - 50-depmod.install     -> depmod resolves its kernel version via
#     `uname -r`, which in a container returns the HOST runner's
#     kernel, and then fails because /lib/modules/<host-kernel> is
#     absent
#
# None of those need to run at image-build time. bootc/ostree
# regenerates the initramfs and updates the boot config at first
# boot on the running system.
#
# Cannot use KERNEL_INSTALL_BYPASS — kernel-install does not honour
# it (verified via `strings` on the binary). Can't use
# KERNEL_INSTALL_LAYOUT=none either — kernel-install still runs the
# plugins for "other" layouts. The only reliable bypass is to move
# the plugin files out of the plugin directory entirely and restore
# them afterwards. Bazzite does a narrower version of the same thing
# in their install-kernel (PR history).
INSTALL_D=/usr/lib/kernel/install.d
INSTALL_D_STASH=/tmp/kernel-install.d.stash
mkdir -p "${INSTALL_D_STASH}"
# Sweep every *.install into the stash. The [[ -e ]] guard handles
# the "no matches" case without needing shopt nullglob.
STASHED_PLUGINS=()
for plugin in "${INSTALL_D}"/*.install; do
    [[ -e "${plugin}" ]] || continue
    mv "${plugin}" "${INSTALL_D_STASH}/$(basename "${plugin}")"
    STASHED_PLUGINS+=("$(basename "${plugin}")")
done
echo "Stashed ${#STASHED_PLUGINS[@]} kernel-install.d plugins"

# Install the pinned kernel RPMs from the akmods bind mount.
# Globs match the bluefin pattern (kernel-[0-9]*.rpm catches kernel-<version>
# only, not kernel-core-* or kernel-modules-*).
dnf5 -y install \
    "${AKMODS_SRC}"/kernel-rpms/kernel-[0-9]*.rpm \
    "${AKMODS_SRC}"/kernel-rpms/kernel-core-*.rpm \
    "${AKMODS_SRC}"/kernel-rpms/kernel-modules-*.rpm \
    "${AKMODS_SRC}"/kernel-rpms/kernel-devel*.rpm

# Install matching common kmods. We only restore what rocinante actually
# uses: framework-laptop (FW13 hardware support) and v4l2loopback (OBS
# virtual cameras). Skip wl, xone, xpadneo, openrazer — not needed here.
dnf5 -y install \
    "${AKMODS_SRC}"/rpms/kmods/kmod-framework-laptop-*.rpm \
    "${AKMODS_SRC}"/rpms/kmods/kmod-v4l2loopback-*.rpm \
    "${AKMODS_SRC}"/rpms/ublue-os/ublue-os-akmods-addons-*.rpm

# Install matching ZFS kmod + userspace built against the pinned kernel.
# Mirror bluefin PR #4187's ZFS_RPMS list (version-number suffixes avoid
# pulling in debug/devel subpackages from /rpms/kmods/zfs/{debug,devel}/),
# plus `zfs` (the main userspace meta at the zfs/ top level) and
# zfs-dracut (which lives under zfs/other/).
dnf5 -y install \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/kmod-zfs-"${KERNEL_PIN}"-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/zfs-[0-9]*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/libnvpair[0-9]-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/libuutil[0-9]-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/libzfs[0-9]-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/libzpool[0-9]-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/python3-pyzfs-*.rpm \
    "${AKMODS_ZFS_SRC}"/rpms/kmods/zfs/other/zfs-dracut-*.rpm

# Nvidia-open variant: restore kmod-nvidia built against the pinned kernel.
# Userspace nvidia libs come from the bluefin-nvidia-open base image and
# are not kernel-version-tied, so they survive the erase unchanged.
if [[ "${BASE_IMAGE}" == *nvidia* ]]; then
    echo "NVIDIA variant detected, installing matching kmod-nvidia"
    dnf5 -y install \
        "${AKMODS_NVIDIA_SRC}"/rpms/kmods/kmod-nvidia-"${KERNEL_PIN}"-*.rpm \
        "${AKMODS_NVIDIA_SRC}"/rpms/ublue-os/ublue-os-nvidia-addons-*.rpm
fi

# Restore every stashed plugin. Subsequent build scripts
# (10-build.sh → 20-1password.sh → ...) and more importantly the
# running system at first boot all need these present so that
# kernel-install works normally. Missing this restore would make the
# installed image unusable.
for plugin in "${STASHED_PLUGINS[@]}"; do
    mv "${INSTALL_D_STASH}/${plugin}" "${INSTALL_D}/${plugin}"
done
rmdir "${INSTALL_D_STASH}"
echo "Restored ${#STASHED_PLUGINS[@]} kernel-install.d plugins"

# Prevent any subsequent dnf5 operation in this or future builds from
# bumping the kernel. The versionlock plugin is present in bluefin:stable
# (used by the same mechanism in PR #4187).
dnf5 versionlock add \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    kernel-devel \
    kernel-devel-matched

# Verify the installed kernel matches the pin. Fail loud if not.
INSTALLED_EVR=$(rpm -q kernel-core --qf '%{EVR}.%{ARCH}\n')
if [[ "${INSTALLED_EVR}" != "${KERNEL_PIN}" ]]; then
    echo "ERROR: kernel-core is ${INSTALLED_EVR}, expected ${KERNEL_PIN}"
    exit 1
fi
echo "Kernel pinned: ${INSTALLED_EVR}"

echo "::endgroup::"
