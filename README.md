# ja720-sd-image

Builds the flashable SD update image for the **Benesse Pocket Challenge 4
(JA720)** Linux port: kernel + initramfs in a single payload that the
**stock loader's SDUPDATE mode** writes into the internal storage, plus
the token file that drives it.

The kernel itself lives in
[mouseos/linux-ja720](https://github.com/mouseos/linux-ja720); this
repository consumes its releases (`zImage`, `ja720.dtb`), builds a tiny
static userland, and assembles the final distributable zip.

## Raw full image (advanced)

If you would rather write the internal SD directly (dd), use
`tools/make-raw-image.py`: it splices JA720LNX.BIN into a copy of your
own stock dump at the kernel offset (0x100000) and produces a raw image
byte-identical to the dump outside the kernel area. See RAW-IMAGE.txt
in the release zip. Note the payload (~8.9 MB) extends past the stock
kernel slot and overwrites the head of the JA720XXX.DAT area; restoring
BestaWin means writing the original dump back.

## What you get

Each release contains `ja720-linux-<kernel-tag>.zip` with:

- `JA720LNX.BIN` — payload: Besta header + entry shim + zImage with
  appended DTB + initramfs (busybox + dropbear, static, ARMv5TE/musl)
- `SDUPDATE.INI` — token file for the stock loader's update mode
- `README.txt` — end-user instructions (Japanese)

The initramfs is the root filesystem: it brings up USB gadget Ethernet
(`192.168.7.2/24`) and dropbear sshd. Default login: `root` / `ja720`
(change it after first login). A shell is also available on the
framebuffer console — the board has no exposed UART, so the display and
SSH are the two debug channels.

## How the payload boots

The stock loader loads the payload to `0x80000000` and calls the entry
at offset `0x20` with its own MMU/cache state. A small shim
(`shim/shim.S`) switches the CPU to the ARM Linux boot protocol state
and branches to the zImage at offset `0x100`. The DTB sits in a fixed
32 KiB slot right after the zImage and points `/chosen` at the initrd
that follows it.

`SDUPDATE.INI` is a flat whitespace-separated token list — the exact
format the loader firmware's parser consumes (name/address pairs for
CODE, DAT0, DAT1, DAT2; address 0 = the kernel area at internal offset
`0x100000`). Only CODE is used; unused slots are `NONE 0`.

## Build

CI (`.github/workflows/build.yml`) runs on push and on demand. The
musl toolchain, source tarballs and the compiled rootfs are kept in
`actions/cache` (keyed by `VERSIONS` + the build script), so repeat
builds only redo what changed. To build the newest kernel release
manually in CI, run the workflow with an optional `kernel_tag` input.

Local assembly from already-downloaded kernel assets works too (place
`zImage` and `ja720.dtb` in `kernel/`):

```sh
sudo apt install gcc-arm-linux-gnueabi device-tree-compiler zip curl
./build-image.sh
```
