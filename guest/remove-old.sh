#!/bin/bash
# Remove every previous copy of virtio-net.kext (Phil Jordan's original 0.9.x
# from the .pkg installer or a manual copy, or an earlier build of ours).
# Called by install.sh; can also be run on its own.
# Usage:  sudo ./remove-old.sh
# Bash 3.2 compatible (the guest's /bin/bash).

BUNDLE_ID="eu.philjordan.virtio-net"

if [ "$(id -u)" != "0" ]; then
    echo "Run with sudo: sudo $0"; exit 1
fi

echo ">> unloading $BUNDLE_ID (if loaded)"
kextunload -b "$BUNDLE_ID" >/dev/null 2>&1

FOUND=0
for dir in /System/Library/Extensions /Library/Extensions /Extra/Extensions; do
    [ -d "$dir" ] || continue
    # By folder name...
    if [ -d "$dir/virtio-net.kext" ]; then
        echo ">> removing $dir/virtio-net.kext"
        rm -rf "$dir/virtio-net.kext"
        FOUND=1
    fi
    # ...and by bundle identifier, in case a copy was renamed.
    for k in "$dir"/*.kext; do
        [ -f "$k/Contents/Info.plist" ] || continue
        if grep -q "<string>$BUNDLE_ID</string>" "$k/Contents/Info.plist" 2>/dev/null; then
            echo ">> removing $k (bundle id $BUNDLE_ID)"
            rm -rf "$k"
            FOUND=1
        fi
    done
done

# Receipt left by the original Virtio-Net-Driver-0.9.4.pkg installer.
if pkgutil --pkgs 2>/dev/null | grep -qx "$BUNDLE_ID"; then
    echo ">> forgetting installer receipt $BUNDLE_ID"
    pkgutil --forget "$BUNDLE_ID" >/dev/null 2>&1
    FOUND=1
fi

if [ $FOUND -eq 0 ]; then
    echo ">> no previous virtio-net.kext found"
fi

echo ">> refreshing kext caches"
touch /System/Library/Extensions
if kextcache -help 2>&1 | grep -q -- "-system-caches"; then
    kextcache -system-caches >/dev/null 2>&1
fi
exit 0
