# CLAUDE.md — virtio-net.kext rebuild for Mac OS X 10.6+

Context for Claude Code. Talk to the user in English. Code, comments and commit messages in English.

## Goal

Get Phil Jordan's virtio-net driver (0.9.4, LGPLv3) loading and working in a **Mac OS X 10.6.8** guest on **UTM / QEMU 10.x, x86_64 TCG emulation, M4 Pro host (macOS 27)**. Then the same binary on 10.7–10.9. Motivation: the best-performing emulated NIC; e1000 works but is register-heavy under TCG.

Sister project with the same build approach, already proven green in CI and working in the guest: https://github.com/brunocastello/qemu-hda-kext (QemuHDAAudio.kext). When in doubt about build/link details, look at how that repo does it.

## Hard rules

- **Never build locally.** No `make`, `make deps`, `make objects`, Xcode, or dependency downloads on the user's Mac. All compilation happens in **GitHub Actions** (`.github/workflows/build.yml`, `macos-15`). Edit, commit, push, then `gh run watch`. On failure, read the logs with `gh run view --log-failed`.
- The user wants Claude Code to do the git/GitHub work: init, `gh repo create`, push, watch, download artifacts with `gh run download`.
- Don't claim networking is fixed until the user confirms it in the guest.

## History / diagnosis so far

- With UTM's `virtio-net-pci`, the guest sees a **legacy/transitional** device: `vendor-id <f41a0000>`, `device-id <00100000>` (0x1000), `class-code <00000200>` (Ethernet), `IOName "ethernet"`. UTM's other virtio devices are also legacy (`pci1af4,1003` virtio-serial, `pci1af4,1005` virtio-rng). So the original matching (`IOPCIPrimaryMatch 0x10001AF4&0xffc0ffff` + Ethernet class) is correct. No QEMU flags needed.
- The prebuilt `bin/virtio-net.kext` from startergo/virtio-net-osx (= pmj 0.9.4b3, built with Xcode 4.6.3 / **10.8 SDK**) fails on 10.6.8:
  `kxld[eu.philjordan.virtio-net]: The super class vtable 'vtable for IOEthernetController' for vtable 'vtable for eu_philjordan_virtio_net' is out of date.` → link error code 5.
- Guest 10.6.8 runs **IONetworkingFamily 1.10** = Apple OSS tag `IONetworkingFamily-65.2.1` (verified by reading that tag's Info.plist).
- The user removed the broken kext and is on e1000 meanwhile.
- **2026-10-22, 0.9.5 (CI run 39831855288) in the 10.6.8 guest:** kextutil OK, loads, `en0` up, DHCP 10.0.3.15 on UTM "Emulated VLAN" (QEMU user-mode net: gw 10.0.3.2, DNS 10.0.3.3). Ping gw OK, TCP by IP OK (`curl http://1.1.1.1` → 301), `dig @10.0.3.3` OK. System DNS failed until `killall mDNSResponder`, then `curl captive.apple.com` → 200. So the driver works (offloading on); the remaining failure is the same mDNSResponder boot stall seen with e1000. `ping 1.1.1.1` fails, which is expected because user-mode net doesn't forward ICMP to the internet.
- Packet counters: the original never filled `IONetworkStats`. Fixed in 0.9.5 (`net_stats`, set in `configureInterface`); the user confirmed it in the guest. Offloads: `IOFeatures = 0` is correct. QEMU's virtio_net_get_features() clears CSUM/HOST_TSO4/GUEST_* when the peer has no vnet_hdr, and UTM's backends (slirp = Emulated VLAN, vmnet = Shared/Bridged/Host) have none. Only Linux tap/vhost has them. So no checksum offload and no TSO on UTM; the driver negotiates before attachInterface(), so it's not a driver bug. Don't revisit unless the backend changes. The VIOLog feature lines don't show in kernel.log.

## What this repo is

```
src/virtio_net.cpp, virtio_net.h, virtio_ring.h   pmj/virtio-net-osx @ 7024815 ("New 0.9.4 release"), 2013.
                                                  NOT the repo's later VirtioFamily rewrite (unfinished).
src/kmod_info.c                                   kmod_info (name = bundle id eu.philjordan.virtio-net).
Resources/Info.plist.in                           original personality + tunables; adds kpi.unsupported.
scripts/fetch-deps.sh                             MacKernelSDK (pinned 3f750085) + IONetworkingFamily-65.2.1 headers
                                                  → deps/ionet-overlay/IOKit/network/*.h
scripts/macho-compat.py                           strips load commands the 10.6 kxld rejects (from qemu-hda-kext).
guest/install.sh                                  runs remove-old.sh, copies, kextutil -n -t, kextload.
guest/remove-old.sh                               removes ANY previous virtio-net.kext (/S/L/E, /L/E, /Extra/Extensions,
                                                  by folder name and by bundle id) + the 0.9.4 .pkg receipt.
guest/uninstall.sh, guest/collect-logs.sh         as named; scripts are bash 3.2 compatible.
```

Bundle id kept as `eu.philjordan.virtio-net` (version 0.9.5, see `VERSION`) so it cleanly replaces the original.

### Source changes vs 0.9.4 (all marked `qemu-virtio-net-kext:`)

1. Explicit `static_cast<uint8_t>` in an initializer list (C++11 narrowing error with modern clang).
2. `pci_dev->configRead32(kIOPCIConfigBaseAddress0)` → `pci_dev->configRead32(pci_dev->space, kIOPCIConfigBaseAddress0)`. In MacKernelSDK's IOPCIDevice.h the one-arg form is an inline wrapper around the non-virtual `extendedConfigRead32()`; in 10.6 it is a virtual. The two-arg virtual has the same vtable slot (268) in both header sets; slots for `ioRead*/ioWrite*`, `setIOEnable`, `getDeviceMemoryWithRegister`, `mapDeviceMemoryWithRegister`, `getInterruptType` were also compared and match (clang `-fdump-vtable-layouts`).

### Build notes

- Same flags as qemu-hda-kext: `-target x86_64-apple-macos10.6 -mkernel -fapple-kext -fno-rtti -fno-exceptions -fno-use-cxa-atexit -fno-stack-protector`, `-mllvm -disable-atexit-based-global-dtor-lowering` (when supported), link with `-Xlinker -kext` + MacKernelSDK `libkmod.a`, then `macho-compat.py`. `make check` fails if `__cxa_atexit`/`___dso_handle`/stack-check symbols appear.
- CI must stay free of warnings and annotations: Node 24 actions (checkout/upload-artifact v7, action-gh-release v3); `-Wno-shadow -Wno-implicit-int-conversion -Wno-sign-conversion` for the untouched 2013 code; IONetworkingFamily is fetched as a tag tarball (git clone of Apple's old tags warns).
- Releases: push tag `vX.Y.Z` (matching `VERSION`) → the workflow attaches the zip; then set the notes with `gh release edit`.
- Include order: `deps/ionet-overlay` **before** MacKernelSDK so the 10.6.8 IONetworkingFamily headers win. This is the actual fix for the vtable error.
- Compile-checked with clang 18 (Linux, `make objects`) before handoff; the Mach-O link has not run yet. Imports compared with the original 10.8 binary: only differences are `IONetworkController::_RESERVEDIONetworkController0/1` (slots that are reserved in 10.6 and were used in 10.8 — exactly the old mismatch), `IOService::message`, and libkmod's `_start/_stop`.
- If kxld on 10.6 complains about a vtable for another class (e.g. `IOService`, `IOPCIDevice`), add that family's 10.6 headers to the overlay the same way (IOPCIFamily OSS tags exist; 10.6-era ≈ `IOPCIFamily-144`…`151.5`).

## Testing in the guest

UTM: Network → Emulated Network Card → `virtio-net-pci`.

```
unzip VirtioNet-<ver>.zip && cd VirtioNet-<ver>
sudo ./install.sh          # removes old copies first
sudo ./collect-logs.sh     # ~/Desktop/virtio-net-report-*.txt
```

Logs: 10.6/10.7 `/var/log/kernel.log`; 10.8/10.9 `/var/log/system.log`; driver logs start with `virtio-net`.

Order of checks if it fails:
1. `kextutil -n -t` output (load/link errors).
2. Loaded but no `en*` interface → driver start failed; kernel log.
3. Interface up, no traffic → set `PJVirtioNetAllowOffloading` false; also try `PJVirtioMaxTransmitDataSegments`.
4. Performance: compare a large download vs e1000 (`curl -o /dev/null -w '%{speed_download}'`).

## Related problem: no DNS at boot (SOLVED 2026-10-22, not the kext)

With any NIC, 10.6.8 under QEMU booted with an IP but no DNS until `killall mDNSResponder`, and the clock didn't sync.
Root cause: QEMU's RTC lacks the upper CMOS bank, so AppleRTC's PM trace reads 0xFF and the kernel logs
`Sleep failure code 0xffffffff 0xffffffff`. configd's PowerManagement.bundle 160.0.0 then indexes the `PCITopLevel`
array with all 32 bits of the PCI mask, unchecked (x86_64 loop at 0x24e5), and segfaults twice per boot. mDNSResponder stays
subscribed to the dead configd (state dump: only lo0, no DNS servers). Fix: `guest/fix-configd-pmtrace.sh` patches
`je 0x258d` at vmaddr 0x2475 (file offset 13429) to `jmp; nop`. The script checks the SHA-256 and keeps a backup. The user confirmed it fixed in the guest.
Public write-up: https://gist.github.com/brunocastello/d3605c048af8f57e691130dfe0ddfac5. RTCMemoryFixup is not an
option on 10.6 (requires 10.8 KPIs). The planned mDNSResponder-restart LaunchDaemon is no longer needed.

Guest file transfer without clipboard: on UTM Emulated VLAN the host's localhost is `10.0.3.2` from the guest, so serve
scripts with `python3 -m http.server --bind 127.0.0.1` and have the guest run `curl -s 10.0.3.2:PORT/x.sh | sh`. Send
results back with `| nc 10.0.3.2 PORT` to a receiver that reads until EOF. (macOS `nc -l` with stdin at EOF truncates.)
