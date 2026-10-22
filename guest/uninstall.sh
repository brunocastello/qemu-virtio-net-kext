#!/bin/bash
# Remove virtio-net.kext (any version) from the guest.
# Usage:  sudo ./uninstall.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$(id -u)" != "0" ]; then
    echo "Run with sudo: sudo $0"; exit 1
fi
"$HERE/remove-old.sh"
echo "Done. Switch UTM's network card back to e1000 if needed, then reboot."
