#!/bin/bash
# Assemble the JA720 SD update image.
#
# Inputs:
#   kernel/zImage    - from the mouseos/linux-ja720 release
#   kernel/ja720.dtb - ditto (downloaded automatically if missing)
#   initramfs.cpio.gz - built by initramfs/build-rootfs.sh
#
# Output (dist/):
#   JA720LNX.BIN  - payload flashed by the stock loader's SDUPDATE mode
#   SDUPDATE.INI  - token file for the stock loader (see below)
#   README.txt    - end-user instructions
#   ja720-linux-<KERNEL_TAG>.zip - everything, for distribution
#
# Payload layout (loaded by the stock loader to 0x80000000):
#   0x000  Besta kernel header (32 bytes): entry 0x80000020,
#          load size, load base 0x80000000, "W55"/"FA93" markers
#   0x020  entry shim (shim/shim.S): MMU/caches off, r0/r1/r2 set,
#          branch to zImage
#   0x100  zImage with the DTB appended (fixed 32 KiB DTB slot; the
#          DTB carries /chosen linux,initrd-start/end pointing at:)
#   ...    initramfs.cpio.gz, right after the DTB slot
#   total size padded to a 512-byte multiple (the flasher requires it)
#
# SDUPDATE.INI is a flat whitespace-separated token list - this is the
# exact format the stock loader's parser consumes (verified against
# the loader firmware): CODE name, CODE addr, DAT0 name, DAT0 addr,
# DAT1 name, DAT1 addr, DAT2 name, DAT2 addr. The address is a byte
# offset relative to the kernel area (0 = internal eSD offset
# 0x100000). Unused slots use the name NONE, which simply fails to
# open and is skipped by the loader.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD

KERNEL_TAG=${KERNEL_TAG:-latest}
mkdir -p kernel work dist

if [ ! -f kernel/zImage ] || [ ! -f kernel/ja720.dtb ]; then
	echo "fetching kernel release assets (tag: $KERNEL_TAG)..."
	if [ "$KERNEL_TAG" = "latest" ]; then
		KERNEL_TAG=$(gh api repos/mouseos/linux-ja720/releases/latest --jq .tag_name)
	fi
	gh release download "$KERNEL_TAG" -R mouseos/linux-ja720 \
		-p zImage -p ja720.dtb -D kernel --clobber
fi
echo "kernel tag: $KERNEL_TAG"

[ -f initramfs.cpio.gz ] || initramfs/build-rootfs.sh

# ---- shim ----
arm-linux-gnueabi-gcc -c -o work/shim.o shim/shim.S
arm-linux-gnueabi-ld -Ttext 0x80000020 -o work/shim.elf work/shim.o
arm-linux-gnueabi-objcopy -O binary work/shim.elf work/shim.bin
SHIM_SIZE=$(stat -c%s work/shim.bin)
[ "$SHIM_SIZE" -le 224 ] || { echo "shim too big: $SHIM_SIZE"; exit 1; }

# ---- DTB: create initrd properties, then fix the size ----
DTB_PAD=32768
cp kernel/ja720.dtb work/ja720.dtb
fdtput -tx work/ja720.dtb /chosen linux,initrd-start 0
fdtput -tx work/ja720.dtb /chosen linux,initrd-end 0
truncate -s $DTB_PAD work/ja720.dtb

ZIMG_SIZE=$(stat -c%s kernel/zImage)
INITRD_OFF=$((0x100 + ZIMG_SIZE + DTB_PAD))
INITRD_OFF=$(( (INITRD_OFF + 511) / 512 * 512 ))
INITRD_SIZE=$(stat -c%s initramfs.cpio.gz)
INITRD_START=$((0x80000000 + INITRD_OFF))
INITRD_END=$((INITRD_START + INITRD_SIZE))
# In-place value update: property sizes are now stable.
fdtput -tx work/ja720.dtb /chosen linux,initrd-start "$(printf '0x%08x' $INITRD_START)"
fdtput -tx work/ja720.dtb /chosen linux,initrd-end "$(printf '0x%08x' $INITRD_END)"

# ---- payload ----
TOTAL=$((INITRD_OFF + INITRD_SIZE))
TOTAL=$(( (TOTAL + 511) / 512 * 512 ))
python3 - "$TOTAL" "$ZIMG_SIZE" "$INITRD_OFF" << 'PY'
import struct, sys
total, zimg_size, initrd_off = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
img = bytearray(total)
hdr = bytearray(32)
struct.pack_into('<I', hdr, 0x00, 0x80000020)   # entry point
struct.pack_into('<I', hdr, 0x08, total)        # load size
struct.pack_into('<I', hdr, 0x0C, 0x80000000)   # load base
struct.pack_into('<I', hdr, 0x10, total)        # size (duplicated, as stock)
hdr[0x14:0x18] = b'W55\0'
hdr[0x18:0x1C] = b'FA93'
img[0:32] = hdr
def place(path, off):
    data = open(path, 'rb').read()
    img[off:off + len(data)] = data
place('work/shim.bin', 0x20)
place('kernel/zImage', 0x100)
place('work/ja720.dtb', 0x100 + zimg_size)
place('initramfs.cpio.gz', initrd_off)
open('work/payload.bin', 'wb').write(img)
print('payload assembled:', total, 'bytes')
PY

# Sanity: the payload must fit the 32 MiB SDRAM window with room to spare.
[ "$TOTAL" -lt 33554432 ] || { echo "payload too large: $TOTAL"; exit 1; }
[ "$(stat -c%s work/payload.bin)" = "$TOTAL" ] || { echo "payload size mismatch"; exit 1; }
cp work/payload.bin dist/JA720LNX.BIN
printf 'JA720LNX.BIN 0\nNONE 0\nNONE 0\nNONE 0\n' > dist/SDUPDATE.INI
cp docs/USAGE.txt dist/README.txt
ZIP="ja720-linux-${KERNEL_TAG}.zip"
( cd dist && rm -f "$ZIP" && zip -q "$ZIP" JA720LNX.BIN SDUPDATE.INI README.txt )
( cd dist && sha256sum JA720LNX.BIN "$ZIP" > SHA256SUMS )
ls -l dist/
echo "initrd: start=$(printf '0x%08x' $INITRD_START) end=$(printf '0x%08x' $INITRD_END) size=$INITRD_SIZE"
echo "payload total: $TOTAL bytes"
