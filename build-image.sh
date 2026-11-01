#!/bin/bash
# Assemble the JA720 Linux payload (JA720LNX.BIN).
# The payload is written at offset 0x100000 of the internal SD
# (see the v1.0.0 release's JA720-LINUX-RAW.img for a ready-made
# dd-able image: stock boot area + this payload).
#
# Inputs:
#   kernel/zImage    - from the mouseos/linux-ja720 release
#   kernel/ja720.dtb - ditto (downloaded automatically if missing)
#   initramfs.cpio.gz - built by initramfs/build-rootfs.sh
#
# Output (dist/):
#   JA720LNX.BIN  - the payload (kernel + initramfs) for offset 0x100000
#   SHA256SUMS
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

