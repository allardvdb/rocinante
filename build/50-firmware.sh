#!/usr/bin/bash
set -eoux pipefail

# Override linux-firmware to fix S0ix regression (linux-firmware-20260221 broke S0ix on Strix Point)
# Follows the Bazzite pattern: pin firmware version via Koji RPMs
# See: https://github.com/bazzite-org/bazzite/issues/4356
#
# This script dynamically discovers all installed linux-firmware sub-packages
# and reinstalls them at the pinned version, so no firmware is lost regardless
# of what hardware the image runs on.

FIRMWARE_VERSION="${FIRMWARE_VERSION:-20260309}"
FIRMWARE_RELEASE="${FIRMWARE_VERSION}-1.fc$(rpm -E %fedora)"
KOJI_BASE="https://kojipkgs.fedoraproject.org/packages/linux-firmware/${FIRMWARE_VERSION}/1.fc$(rpm -E %fedora)/noarch"

echo "::group:: Override linux-firmware to ${FIRMWARE_VERSION}"

# Discover all currently installed linux-firmware sub-packages.
# The glob catches linux-firmware and linux-firmware-whence directly.
# The whatrequires query catches all sub-packages that depend on
# linux-firmware-whence (and would be cascade-removed).
mapfile -t INSTALLED_PKGS < <(
    {
        rpm -qa --qf '%{NAME}\n' 'linux-firmware*' 2>/dev/null || true
        rpm -q --whatrequires linux-firmware-whence --qf '%{NAME}\n' 2>/dev/null || true
    } | sort -u
)

if [[ ${#INSTALLED_PKGS[@]} -eq 0 ]]; then
    echo "ERROR: No linux-firmware packages found in base image. Cannot proceed."
    exit 1
fi

echo "Discovered ${#INSTALLED_PKGS[@]} firmware packages to reinstall:"
printf '  %s\n' "${INSTALLED_PKGS[@]}"

# Build Koji URL list for all discovered packages.
KOJI_URLS=()
for pkg in "${INSTALLED_PKGS[@]}"; do
    KOJI_URLS+=("${KOJI_BASE}/${pkg}-${FIRMWARE_RELEASE}.noarch.rpm")
done

# Validate all URLs exist on Koji BEFORE removing anything.
# This catches package renames or missing packages at the pinned version
# without leaving the image in a broken state.
echo "Validating ${#KOJI_URLS[@]} Koji URLs..."
for url in "${KOJI_URLS[@]}"; do
    if ! curl -sf -I --max-time 10 --retry 2 "$url" > /dev/null; then
        echo "ERROR: Package not found on Koji: ${url}"
        echo "The pinned FIRMWARE_VERSION=${FIRMWARE_VERSION} may not have this package."
        echo "Check Koji for available sub-packages at this version."
        exit 1
    fi
done
echo "All URLs validated."

echo "Removing existing linux-firmware packages..."
dnf5 -y remove linux-firmware\* || { rc=$?; echo "WARNING: dnf5 remove exited ${rc}, continuing..."; }

echo "Installing linux-firmware ${FIRMWARE_RELEASE} from Koji..."
dnf5 -y install "${KOJI_URLS[@]}"

echo "Installed firmware version:"
rpm -q linux-firmware
echo "::endgroup::"
