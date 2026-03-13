#!/usr/bin/bash
set -eoux pipefail

# Override linux-firmware to fix S0ix regression (linux-firmware-20260221 broke S0ix on Strix Point)
# Follows the Bazzite pattern: pin firmware version via Koji RPMs
# See: https://github.com/bazzite-org/bazzite/issues/4356

FIRMWARE_VERSION="${FIRMWARE_VERSION:-20260309}"
FIRMWARE_RELEASE="${FIRMWARE_VERSION}-1.fc$(rpm -E %fedora)"
KOJI_BASE="https://kojipkgs.fedoraproject.org/packages/linux-firmware/${FIRMWARE_VERSION}/1.fc$(rpm -E %fedora)/noarch"

echo "::group:: Override linux-firmware to ${FIRMWARE_VERSION}"
echo "Removing existing linux-firmware packages..."
dnf5 -y remove linux-firmware\* || echo "WARNING: dnf5 remove exited $?, continuing..."

echo "Installing linux-firmware ${FIRMWARE_RELEASE} from Koji..."
dnf5 -y install \
    "${KOJI_BASE}/linux-firmware-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/linux-firmware-whence-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/amd-gpu-firmware-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/amd-ucode-firmware-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/mediatek-firmware-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/realtek-firmware-${FIRMWARE_RELEASE}.noarch.rpm" \
    "${KOJI_BASE}/cirrus-audio-firmware-${FIRMWARE_RELEASE}.noarch.rpm"

echo "Installed firmware version:"
rpm -q linux-firmware
echo "::endgroup::"
