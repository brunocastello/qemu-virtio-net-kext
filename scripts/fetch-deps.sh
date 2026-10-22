#!/bin/bash
# Fetch build dependencies into deps/ (idempotent). Runs in CI.
#
#  - MacKernelSDK (acidanthera): lets a modern Xcode build kexts for old
#    kernels; provides libkmod.a for 10.6+ x86_64 and the generic kernel
#    headers.
#  - IONetworkingFamily headers from Mac OS X 10.6.8 (IONetworkingFamily 1.10,
#    Apple open source tag IONetworkingFamily-65.2.1, APSL 2.0).
#
# Why the old headers matter: the original virtio-net.kext 0.9.4 was built
# with the 10.8 SDK, whose IOEthernetController has more virtual methods than
# 10.6's. Snow Leopard's kernel linker then refuses it with
#   "The super class vtable 'vtable for IOEthernetController' ... is out of date".
# Compiling against the OLDEST family we support fixes that; newer families
# (10.7-10.9) stay binary compatible with kexts built against older headers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/deps"

MKSDK_REPO="${MKSDK_REPO:-https://github.com/acidanthera/MacKernelSDK.git}"
MKSDK_REV="${MKSDK_REV:-3f750085caa17ec3a7880f11c11bf4f48cd6a164}"

IONF_REPO="${IONF_REPO:-https://github.com/apple-oss-distributions/IONetworkingFamily.git}"
IONF_TAG="${IONF_TAG:-IONetworkingFamily-65.2.1}"   # CFBundleVersion 1.10 (10.6.8)

mkdir -p "$DEPS"

# --- MacKernelSDK ---------------------------------------------------------
if [ ! -d "$DEPS/MacKernelSDK/.git" ]; then
    echo ">> cloning MacKernelSDK"
    git clone --quiet "$MKSDK_REPO" "$DEPS/MacKernelSDK"
fi
git -C "$DEPS/MacKernelSDK" fetch --quiet origin "$MKSDK_REV" 2>/dev/null || true
git -c advice.detachedHead=false -C "$DEPS/MacKernelSDK" checkout --quiet "$MKSDK_REV"
echo ">> MacKernelSDK @ $(git -C "$DEPS/MacKernelSDK" rev-parse --short HEAD)"

# --- IONetworkingFamily headers -------------------------------------------
OVERLAY="$DEPS/ionet-overlay/IOKit/network"
STAMP="$DEPS/ionet-overlay/.tag"
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$IONF_TAG" ]; then
    echo ">> fetching $IONF_TAG headers"
    TMP="$(mktemp -d)"
    # Tarball rather than `git clone --branch`: Apple's old OSS tags point at
    # tag objects git warns about ("... is not a commit!").
    mkdir -p "$TMP/IONetworkingFamily"
    curl -fsSL "${IONF_REPO%.git}/archive/refs/tags/$IONF_TAG.tar.gz" \
        | tar xzf - -C "$TMP/IONetworkingFamily" --strip-components 1
    rm -rf "$DEPS/ionet-overlay"
    mkdir -p "$OVERLAY"
    cp "$TMP"/IONetworkingFamily/*.h "$OVERLAY/"
    echo "$IONF_TAG" > "$STAMP"
    rm -rf "$TMP"
fi
echo ">> IONetworkingFamily headers: $(cat "$STAMP")"
