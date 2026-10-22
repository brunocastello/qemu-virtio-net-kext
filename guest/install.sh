#!/bin/bash
# Install the rebuilt virtio-net.kext inside the Mac OS X guest (10.6 - 10.9).
# Removes any previous virtio-net.kext first (see remove-old.sh).
# Usage:  sudo ./install.sh [path/to/virtio-net.kext]
# Bash 3.2 compatible (the guest's /bin/bash).

HERE="$(cd "$(dirname "$0")" && pwd)"
KEXT_SRC="${1:-$HERE/virtio-net.kext}"
DEST="/System/Library/Extensions"
NAME="virtio-net.kext"
BUNDLE_ID="eu.philjordan.virtio-net"

if [ "$(id -u)" != "0" ]; then
    echo "Run with sudo: sudo $0 $*"; exit 1
fi
if [ ! -d "$KEXT_SRC" ]; then
    echo "Kext not found: $KEXT_SRC"; exit 1
fi
if [ "$(uname -m)" != "x86_64" ]; then
    echo "This kext is x86_64 only, but the kernel is $(uname -m)."
    echo "Boot the 64-bit kernel (boot-arg arch=x86_64) and try again."
    exit 1
fi

echo "== 1/4 removing previous versions"
"$HERE/remove-old.sh" || exit 1

echo "== 2/4 copying to $DEST"
cp -R "$KEXT_SRC" "$DEST/$NAME" || exit 1
chown -R root:wheel "$DEST/$NAME"
find "$DEST/$NAME" -type d -exec chmod 755 {} \;
find "$DEST/$NAME" -type f -exec chmod 644 {} \;

echo "== 3/4 validating (kextutil -n -t)"
kextutil -n -t "$DEST/$NAME"
RC=$?

touch "$DEST"
if kextcache -help 2>&1 | grep -q -- "-system-caches"; then
    kextcache -system-caches >/dev/null 2>&1
fi

if [ $RC -ne 0 ]; then
    echo
    echo "kextutil reported problems (see above). Not loading."
    echo "Run: sudo ./collect-logs.sh  and send the report."
    exit 1
fi

echo "== 4/4 loading"
kextload "$DEST/$NAME"
sleep 3
kextstat | grep -i "$BUNDLE_ID"
echo
ifconfig -a | grep -E "^en[0-9]"
echo
echo "Done. If a new 'Ethernet' interface appears, open System Preferences >"
echo "Network once so it gets configured (DHCP by default)."
echo "Rebooting once is recommended."
