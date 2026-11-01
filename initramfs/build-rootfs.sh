#!/bin/bash
# Build the JA720 initramfs rootfs (busybox + dropbear, static, ARMv5TE).
#
# The W55FA93 is an ARM926EJ-S (ARMv5TE), so the userland must not
# contain ARMv6/v7 instructions: everything is built with the musl
# armv5l cross toolchain and static linking (no NSS/dlopen surprises,
# tiny footprint for the 32 MiB RAM).
#
# Cache-friendly layout (used by CI through actions/cache):
#   cache/  - downloaded tarballs and the extracted toolchain
#   build/  - compiled outputs; build/.stamp guards against rebuilds
# Output: initramfs.cpio.gz in the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
. ./VERSIONS

CACHE=$ROOT/cache
BUILD=$ROOT/build
STAMP=$(cat VERSIONS initramfs/build-rootfs.sh | md5sum | cut -d' ' -f1)

if [ -f "$BUILD/.stamp" ] && [ "$(cat "$BUILD/.stamp")" = "$STAMP" ] && \
   [ -f "$ROOT/initramfs.cpio.gz" ]; then
	echo "rootfs: up to date (stamp match), skipping rebuild"
	exit 0
fi

mkdir -p "$CACHE" "$BUILD"
dl() { [ -f "$2" ] || curl -fL --retry 3 --connect-timeout 30 -o "$2" "$1"; }
CROSS_TAR=$CACHE/$(basename "$MUSL_TOOLCHAIN_URL")
dl "$MUSL_TOOLCHAIN_URL" "$CROSS_TAR"
if [ ! -d "$CACHE/toolchain" ]; then
	mkdir -p "$CACHE/toolchain"
	tar -xJf "$CROSS_TAR" -C "$CACHE/toolchain" --strip-components=1
fi
export PATH="$CACHE/toolchain/bin:$PATH"
# Discover the compiler prefix (e.g. armv5-eabi-)
GCC_BIN=$(basename "$(ls "$CACHE/toolchain/bin/"*-gcc | head -1)")
CROSS=${GCC_BIN%gcc}
${CROSS}gcc --version | head -1

BB_TAR=$CACHE/busybox-$BUSYBOX_VERSION.tar.bz2
dl "$BUSYBOX_URL" "$BB_TAR"
DB_TAR=$CACHE/dropbear-$DROPBEAR_VERSION.tar.bz2
dl "$DROPBEAR_URL" "$DB_TAR"

# ---- busybox (static) ----
rm -rf "$BUILD/busybox-$BUSYBOX_VERSION"
tar -xjf "$BB_TAR" -C "$BUILD"
cd "$BUILD/busybox-$BUSYBOX_VERSION"
make -s CROSS_COMPILE=$CROSS defconfig >/dev/null
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
make -s CROSS_COMPILE=$CROSS -j"$(nproc)" >/dev/null
ROOTFS=$BUILD/rootfs
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
make -s CROSS_COMPILE=$CROSS CONFIG_PREFIX="$ROOTFS" install >/dev/null
cd "$ROOT"

# ---- dropbear (static, musl) ----
rm -rf "$BUILD/dropbear-$DROPBEAR_VERSION"
tar -xjf "$DB_TAR" -C "$BUILD"
cd "$BUILD/dropbear-$DROPBEAR_VERSION"
./configure --host="${CROSS%-}" --enable-static \
	--disable-zlib --disable-syslog >/dev/null
make -s -j"$(nproc)" PROGRAMS="dropbear dropbearkey" >/dev/null
cp dropbear dropbearkey "$ROOTFS/usr/sbin/" 2>/dev/null || \
	cp dropbear dropbearkey "$ROOTFS/sbin/"
cd "$ROOT"

# ---- assemble rootfs ----
cp -a initramfs/rootfs-overlay/. "$ROOTFS/"
mkdir -p "$ROOTFS"/{proc,sys,dev,root,run,tmp}
chmod 755 "$ROOTFS/init"
chmod 600 "$ROOTFS/etc/shadow"
# The kernel needs a console node in the initramfs image itself.
if [ ! -e "$ROOTFS/dev/console" ]; then
	sudo mknod -m 600 "$ROOTFS/dev/console" c 5 1
	sudo mknod -m 666 "$ROOTFS/dev/null" c 1 3
fi

# ---- pack ----
( cd "$ROOTFS" && find . | cpio -o -H newc --quiet ) | gzip -9 > "$ROOT/initramfs.cpio.gz"
echo "$STAMP" > "$BUILD/.stamp"
ls -l "$ROOT/initramfs.cpio.gz"
