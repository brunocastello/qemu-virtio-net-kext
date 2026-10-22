#!/bin/bash
# Gather everything needed to debug virtio-net.kext into one text file on the
# Desktop, ready to copy to the host and paste into Claude Code.
# Usage:  sudo ./collect-logs.sh

OUT="$HOME/Desktop/virtio-net-report-$(date +%Y%m%d-%H%M%S).txt"
[ -n "$SUDO_USER" ] && OUT="/Users/$SUDO_USER/Desktop/$(basename "$OUT")"

{
    echo "=== sw_vers / uname"; sw_vers; uname -a
    echo; echo "=== kextstat (network related)"
    kextstat | grep -iE "virtio|IONetworking|IOPCIFamily|8254|e1000"
    echo; echo "=== kextutil -n -t"
    for d in /System/Library/Extensions /Library/Extensions; do
        [ -d "$d/virtio-net.kext" ] && kextutil -n -t "$d/virtio-net.kext" 2>&1
    done
    echo; echo "=== installed copies"
    ls -ld /System/Library/Extensions/virtio-net.kext /Library/Extensions/virtio-net.kext 2>&1
    defaults read /System/Library/Extensions/virtio-net.kext/Contents/Info CFBundleVersion 2>&1
    echo; echo "=== kernel log (virtio)"
    [ -f /var/log/kernel.log ] && grep -i "virtio" /var/log/kernel.log | tail -150
    grep -i "virtio" /var/log/system.log 2>/dev/null | tail -150
    echo; echo "=== PCI network devices"
    ioreg -l -w0 -r -c IOPCIDevice | grep -E '"(IOName|device-id|vendor-id|class-code)"'
    echo; echo "=== ioreg: driver"
    ioreg -l -w0 -r -c eu_philjordan_virtio_net 2>/dev/null | head -200
    echo; echo "=== ifconfig -a"; ifconfig -a
    echo; echo "=== netstat -rn"; netstat -rn
    echo; echo "=== DNS"; cat /etc/resolv.conf 2>&1; scutil --dns 2>&1 | head -30
    echo; echo "=== quick connectivity test"
    ping -c 3 -t 5 1.1.1.1 2>&1
    curl -sS -m 10 -o /dev/null -w "http %{http_code} in %{time_total}s\n" http://captive.apple.com/ 2>&1
} > "$OUT" 2>&1

[ -n "$SUDO_USER" ] && chown "$SUDO_USER" "$OUT"
echo "Report written to $OUT"
