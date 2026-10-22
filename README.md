# virtio-net.kext

> [!CAUTION]
> ### 🤖 AI-Generated Code Ahead
> **This entire repository was crafted with the help of AI.**
>
> If you are allergic to neural networks, synthesized functions, or autocomplete on steroids, **this repository is not for you**.
> You are kindly invited to close this page and write your code line-by-line in `ed` or `vim`. Everyone else, enjoy!

A network driver for **Mac OS X 10.6–10.9** virtual machines running in **UTM / QEMU**, including on Apple Silicon Macs where the guest is emulated.

It's Phil Jordan's [virtio-net driver](https://github.com/pmj/virtio-net-osx) 0.9.4, rebuilt so it finally loads on Snow Leopard. The original refused to load there, with "super class vtable … is out of date". virtio-net moves packets through shared memory, so an emulated guest does less work than with the default Intel e1000 card.

Tested on Mac OS X 10.6.8 in UTM (QEMU 10) on an M4 Pro Mac. 10.7–10.9 should work but are untested. 64-bit kernel only.

## Set up the VM in UTM

In the VM's settings, go to **Network → Emulated Network Card** and pick **virtio-net-pci**. No custom QEMU arguments are needed.

## Install

Download `VirtioNet-<version>.zip` from [Releases](../../releases) and copy it into the guest. Then:

```sh
unzip VirtioNet-<version>.zip
cd VirtioNet-<version>
sudo ./install.sh
```

The installer first removes any older virtio-net.kext, including the original 0.9.4 package. Then open *System Preferences → Network* once and reboot.

To remove it: `sudo ./uninstall.sh`.

## No internet after boot on 10.6? Read this

If the network shows **connected with an IP address**, but websites don't load until you restart `mDNSResponder`, and the clock doesn't sync, the cause isn't this driver. It happens with e1000 too.

Snow Leopard's network configuration daemon (configd) crashes at every boot under QEMU, because of an Apple bug triggered by a missing piece of QEMU's emulated clock chip. One script fixes it (10.6.8 only; it checks the file first and keeps a backup):

```sh
sudo ./fix-configd-pmtrace.sh   # then reboot
```

The full story is in [this gist](https://gist.github.com/brunocastello/d3605c048af8f57e691130dfe0ddfac5).

## If something goes wrong

```sh
sudo ./collect-logs.sh
```

This writes a report to the Desktop. To get back online quickly, switch UTM to e1000 and run `sudo ./uninstall.sh`.

## Limitations

- No checksum or TCP segmentation offload on UTM. QEMU only offers them with Linux `tap` networking, and UTM uses slirp or vmnet. The driver supports them and turns them on wherever QEMU offers them.
- No promiscuous mode, so packet sniffers only see this VM's own traffic.
- No VLAN filtering.

## License

The driver is © Phil Jordan, LGPLv3 (see `LICENSE`), with portions from IBM and Red Hat. The changes in this repository are small and marked `qemu-virtio-net-kext:` in the source. Builds run on GitHub Actions only.
