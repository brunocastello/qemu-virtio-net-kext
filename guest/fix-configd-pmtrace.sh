#!/bin/bash
# Patch 10.6.8 PowerManagement.bundle (configd plugin, v160.0.0) so it no longer
# walks the "prior boot PCI failure" bitmask. Under QEMU, AppleRTC reads the PM
# trace from unimplemented CMOS bytes (0xFFFFFFFF), and the plugin indexes the
# PCITopLevel array with all 32 bits, unchecked -> configd segfaults at boot.
# Patch: x86_64 slice, vmaddr 0x2475: je 0x258d -> jmp 0x258d; nop.
set -e
BIN=/System/Library/SystemConfiguration/PowerManagement.bundle/Contents/MacOS/PowerManagement
BAK=/Library/Preferences/PowerManagement.orig-160.0.0
ORIG=5e5924987850a92148fae71f45d401f90713e509366a92f30ea80aaf043e9141
NEW=0efe4edee1fb8942cfd1bf4301df78fc7b00f3662c3b5a12d6c1bce3577244ed
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cur=$(shasum -a 256 "$BIN" | cut -d' ' -f1)
if [ "$cur" = "$NEW" ]; then echo "already patched"; exit 0; fi
[ "$cur" = "$ORIG" ] || { echo "unexpected PowerManagement binary ($cur), not touching it"; exit 1; }
cp -p "$BIN" "$BAK"
cp -p "$BIN" /tmp/PM.new
printf '\351\023\001\000\000\220' | dd of=/tmp/PM.new bs=1 seek=13429 conv=notrunc 2>/dev/null
[ "$(shasum -a 256 /tmp/PM.new | cut -d' ' -f1)" = "$NEW" ] || { echo "patch verification failed, nothing changed"; exit 1; }
cat /tmp/PM.new > "$BIN"; rm /tmp/PM.new
echo "patched. backup: $BAK"
echo "undo: sudo cp -p $BAK $BIN"
echo "reboot to test."
