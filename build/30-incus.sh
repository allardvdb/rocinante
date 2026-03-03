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
