# virtio-net.kext for Mac OS X 10.6–10.9 on QEMU/UTM

Phil Jordan's [virtio-net driver](https://github.com/pmj/virtio-net-osx) **0.9.4**, rebuilt so it loads on **Snow Leopard**.

The original binary was compiled with the 10.8 SDK. Snow Leopard refuses to load it:

```
kxld[eu.philjordan.virtio-net]: The super class vtable 'vtable for IOEthernetController'
for vtable 'vtable for eu_philjordan_virtio_net' is out of date.
```

This build uses the same source, compiled against Snow Leopard's own networking headers (IONetworkingFamily 1.10). Newer systems accept drivers built against older headers, so the same binary should also load on 10.7–10.9. It is x86_64 only: the guest must boot the 64-bit kernel (`uname -m` → `x86_64`).

## Why virtio-net instead of e1000

Under x86 emulation (UTM on Apple Silicon), every instruction the guest runs is expensive.

- **Fewer register accesses:** virtio-net exchanges packets through shared memory rings, with far fewer register accesses than the emulated Intel e1000 chip.
- **Offloads:** it hands checksums and TCP segmentation to the host, where they run at native speed.

Expect lower guest CPU use and better throughput. This hasn't been benchmarked on this setup yet.

## Get the kext

GitHub Actions builds it on every push. Open **Actions**, then the latest `build` run, and download the `VirtioNet-…` artifact. It contains `VirtioNet-<version>.zip` with the kext and the scripts.

## UTM settings

Go to **Network → Emulated Network Card** and choose `virtio-net-pci`.

UTM attaches it in legacy/transitional mode (PCI ID `1af4:1000`), which is what the driver needs. To check from the guest:

```sh
ioreg -l -w0 -r -c IOPCIDevice | grep -E '"(IOName|device-id|vendor-id)"'
```

You should see `vendor-id <f41a0000>`, `device-id <00100000>` and `IOName "ethernet"`.

## Install in the guest

**The installer removes any previous virtio-net.kext first.** That includes Phil Jordan's original 0.9.4, whether it came from the `.pkg` or a manual copy, and earlier builds of this project. It looks in `/System/Library/Extensions`, `/Library/Extensions` and `/Extra/Extensions`, by folder name and by bundle ID, and it removes the old `.pkg` receipt.

```sh
unzip VirtioNet-<version>.zip
cd VirtioNet-<version>
sudo ./install.sh
```

To only remove old copies, without installing, run `sudo ./remove-old.sh`. To remove this one too, run `sudo ./uninstall.sh`.

To remove the old kext by hand instead:

```sh
sudo kextunload -b eu.philjordan.virtio-net
sudo rm -rf /System/Library/Extensions/virtio-net.kext /Library/Extensions/virtio-net.kext
sudo pkgutil --forget eu.philjordan.virtio-net
sudo touch /System/Library/Extensions
```

After installing:

1. A new Ethernet interface appears. Open *System Preferences → Network* once so it gets configured (DHCP by default).
2. Reboot once.

## If something goes wrong

```sh
sudo ./collect-logs.sh
```

This writes a report to the Desktop with load errors, kernel log, interfaces, routes, DNS and a connectivity test.

- **Link up but traffic broken:** set `PJVirtioNetAllowOffloading` to `false` in `/System/Library/Extensions/virtio-net.kext/Contents/Info.plist`, then reboot.
- **Need network now:** switch UTM back to e1000 and run `sudo ./uninstall.sh`.

### 10.6: connected, has an IP, but no DNS until mDNSResponder is restarted

This isn't the driver. It happens with e1000 too. Under QEMU, 10.6's configd crashes at every boot: its
PowerManagement plugin reads past the end of an array while decoding a bogus "prior boot failure" code,
which AppleRTC reads from CMOS bytes QEMU doesn't implement (`Sleep failure code 0xffffffff 0xffffffff`
in `kernel.log`). mDNSResponder then never sees the network. The clock doesn't sync either, because ntpd can't resolve its server.

Fix (10.6.8 only; checks the binary's hash, keeps a backup):

```sh
sudo ./fix-configd-pmtrace.sh   # then reboot
```

Full write-up: https://gist.github.com/brunocastello/d3605c048af8f57e691130dfe0ddfac5

## Limitations (from the original driver)

- No large-receive reassembly.
- No MAC address filtering or promiscuous mode, so packet sniffers won't see other hosts' traffic.
- No VLAN filtering.
- Modern-only virtio devices (`1af4:1041`) aren't supported. UTM doesn't use them.

## License

The driver is © Phil Jordan, LGPLv3 (see `LICENSE`). It also includes portions from IBM and Red Hat. The build downloads Apple's IONetworkingFamily headers and acidanthera's MacKernelSDK (both APSL 2.0). The changes in this repository are minimal and marked `qemu-virtio-net-kext:` in the source.
