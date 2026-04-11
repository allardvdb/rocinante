#!/usr/bin/bash
set -eoux pipefail

echo "::group:: Install Incus"
dnf5 install -y \
    incus \
    incus-tools \
    qemu-system-x86-core \
    qemu-device-display-virtio-gpu \
    qemu-device-display-virtio-vga \
    qemu-ui-spice-core \
    qemu-char-spice \
    qemu-audio-spice \
    virt-viewer \
    edk2-ovmf \
    swtpm
echo "::endgroup::"

echo "::group:: Override broken Fedora incus-agent with upstream binary"
# Workaround for Fedora bug #2419661 — the Fedora incus-agent binary is built
# with GO111MODULE=off and fails "websocket: bad handshake" inside VMs, which
# breaks `incus exec`, `incus file push/pull`, and VM IP discovery via
# `incus list`. Replace with the upstream prebuilt static binary, version-
# matched to the installed `incus` package so host + agent stay in sync.
INCUS_VERSION="$(rpm -q --queryformat '%{VERSION}' incus)"
INCUS_AGENT_URL="https://github.com/lxc/incus/releases/download/v${INCUS_VERSION}/bin.linux.incus-agent.x86_64"
echo "Validating upstream agent URL: ${INCUS_AGENT_URL}"
if ! curl -sf -I --max-time 10 --retry 2 "${INCUS_AGENT_URL}" > /dev/null; then
    echo "ERROR: upstream incus-agent not found at ${INCUS_AGENT_URL}"
    echo "The Fedora incus version (${INCUS_VERSION}) may not have a matching upstream tag."
    exit 1
fi
curl -fL --retry 3 --max-time 60 -o /usr/bin/incus-agent "${INCUS_AGENT_URL}"
chmod 0755 /usr/bin/incus-agent
file /usr/bin/incus-agent
sha256sum /usr/bin/incus-agent
echo "::endgroup::"

echo "::group:: Configure Incus Services"
systemctl preset incus.socket
systemctl preset incus-user.socket
echo "::endgroup::"

echo "::group:: Configure VFIO for GPU Passthrough"
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/vfio.conf <<'EOF'
add_drivers+=" vfio vfio_iommu_type1 vfio_pci "
EOF
echo "::endgroup::"

echo "::group:: Configure Incus Groups"
# incus and incus-admin groups are created by the package
# Users are added at runtime via ujust or manually
cat > /usr/lib/sysusers.d/incus-groups.conf <<'EOF'
# Ensure incus groups exist for user membership
g incus -
g incus-admin -
EOF
echo "::endgroup::"
