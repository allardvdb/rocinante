#!/usr/bin/bash
# Unmount GVFS/FUSE before suspend to prevent silent suspend failures
# Adapted from: https://github.com/omarchy/omarchy
# See also: https://github.com/ublue-os/bluefin/issues/4123

case "$1" in
    pre)
        # Lazy-unmount all gvfsd-fuse mounts to prevent suspend blocking
        findmnt -t fuse.gvfsd-fuse -n -o TARGET 2>/dev/null | while IFS= read -r mount; do
            umount -l "$mount" 2>/dev/null || true
        done
        ;;
    post)
        # Restart gvfs-daemon after resume to restore mounts
        for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
            if systemctl --user -M "${uid}@" is-active gvfs-daemon.service &>/dev/null; then
                systemctl --user -M "${uid}@" restart gvfs-daemon.service 2>/dev/null || true
            fi
        done
        ;;
esac
