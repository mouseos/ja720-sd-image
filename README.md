# ja720-sd-image

Builds the Linux payload for the **Benesse Pocket Challenge 4 (JA720)**
port and ships it as a raw image for the internal SD.

The kernel lives in
[mouseos/linux-ja720](https://github.com/mouseos/linux-ja720); this
repository consumes its releases (`zImage`, `ja720.dtb`), builds a tiny
static userland (busybox + dropbear, ARMv5TE/musl), and assembles the
payload.

## The release

`JA720-LINUX-RAW.img` (9,943,040 bytes) is the whole deliverable: the
stock boot area (offsets 0–0x100000) followed by the payload at offset
0x100000. Write it directly to the internal SD:

```sh
dd if=JA720-LINUX-RAW.img of=<internal SD> bs=4M status=progress
```

Only 0x0–0x97B800 is written; everything past that on the card stays as
it is. Note the payload extends past the stock kernel slot (0x430000)
and overwrites the head of the JA720XXX.DAT area — BestaWin will not
boot from this card afterwards; restore by writing a stock dump back.

## Payload layout

Loaded by the stock loader to `0x80000000`:

- `0x000` Besta kernel header (entry 0x80000020, load base 0x80000000,
  size, `W55`/`FA93` markers)
- `0x020` entry shim (`shim/shim.S`): CPU into ARM Linux boot protocol
  state, branch to the zImage
- `0x100` zImage, followed by the DTB in a fixed 32 KiB slot whose
  `/chosen` points at the initramfs that follows it
- total size padded to a 512-byte multiple

The initramfs is the root filesystem. The board has no USB port and no
exposed UART, so the debug channels are the framebuffer console and
the boot log the initramfs writes to `JA720LOG.TXT` on the SD card
(dmesg, refreshed every 30 s). Login: `root` / `ja720`.

## Build

CI (`.github/workflows/build.yml`) runs on push and on demand and
uploads the payload as a build artifact. The musl toolchain, source
tarballs and the compiled rootfs are kept in `actions/cache` (keyed by
`VERSIONS` + the build scripts + the rootfs overlay), so repeat builds
only redo what changed. Releases are cut manually; CI does not publish
them.

`tools/make-raw-image.py` documents how the raw image is assembled: it
splices the payload into a stock dump at offset 0x100000 and verifies
that everything outside the kernel area is untouched.
