#!/usr/bin/bash
set -eoux pipefail
# shellcheck source=build/copr-helpers.sh
source /ctx/build/copr-helpers.sh
shopt -s nullglob

echo "::group:: Install Brew"
rsync -rvK /ctx/oci/brew/ /
systemctl preset brew-setup.service
systemctl preset brew-update.timer
systemctl preset brew-upgrade.timer
echo "::endgroup::"

echo "::group:: Copy Custom Files"
# Brewfiles
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/
# Ujust recipes → 60-custom.just (bluefin's 00-entry.just imports this)
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just
echo "::endgroup::"

echo "::group:: Install Packages"
dnf5 install -y --skip-unavailable tmux gnupg2-scdaemon
# nvidia-container-toolkit (nvidia variants only)
if dnf5 repolist --disabled | grep -q nvidia-container-toolkit; then
    dnf5 install -y --enablerepo=nvidia-container-toolkit nvidia-container-toolkit
fi
echo "::endgroup::"

echo "::group:: System Configuration"
systemctl enable podman.socket
systemctl disable pcscd.socket
echo "::endgroup::"

# Run additional build scripts
/ctx/build/20-1password.sh

shopt -u nullglob
echo "Build complete!"
