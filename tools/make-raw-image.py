#!/usr/bin/env python3
"""Build a full raw internal-SD image (same layout as a stock dump).

Takes your own dump of the JA720 internal SD (e.g. PQB) and the Linux
payload (JA720LNX.BIN from the release), and writes a new raw image
that is byte-identical to the dump except for the kernel area, where
the Linux payload replaces the stock BestaWin kernel.

The result can be written straight back to the internal SD with dd.

Usage:
    make-raw-image.py DUMP PAYLOAD [OUTPUT]
    (OUTPUT defaults to PQB-JA720-LINUX.img next to the dump)

Layout facts (from the loader analysis):
  - kernel area starts at byte offset 0x100000 (LBA 0x800); the loader
    reads the header there and loads `size` bytes to 0x80000000.
  - the stock kernel slot is 0x100000-0x430000, followed by
    JA720XXX.DAT at 0x430000 and JA720APX.DAT at 0x1C30000.
  - the Linux payload is larger than the stock slot, so it also
    overwrites the first part of the JA720XXX.DAT area (BestaWin data;
    irrelevant once Linux boots, and restored by writing the original
    dump back). It never reaches JA720APX.DAT or the FAT partition
    at 0x22C30000 - the script refuses payloads that would.
"""
import hashlib
import os
import struct
import sys

KERNEL_OFF = 0x100000
APX_OFF = 0x1C30000  # JA720APX.DAT start; payload must end before this


def sha256_range(f, off, size):
    h = hashlib.sha256()
    f.seek(off)
    left = size
    while left > 0:
        chunk = f.read(min(1 << 20, left))
        if not chunk:
            break
        h.update(chunk)
        left -= len(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    dump_path, payload_path = sys.argv[1], sys.argv[2]
    out_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
        os.path.dirname(os.path.abspath(dump_path)), "PQB-JA720-LINUX.img")

    payload = open(payload_path, "rb").read()
    if len(payload) % 512 != 0:
        print("error: payload size is not a multiple of 512")
        return 1
    entry, _u, size, base, size2 = struct.unpack_from("<5I", payload, 0)
    if (entry, base) != (0x80000020, 0x80000000) or size != len(payload) \
            or size2 != len(payload) \
            or payload[0x14:0x18] != b"W55\0" or payload[0x18:0x1C] != b"FA93":
        print("error: payload header does not look like a JA720 kernel image")
        return 1
    end = KERNEL_OFF + len(payload)
    if end > APX_OFF:
        print("error: payload would overwrite JA720APX.DAT (ends 0x%x)" % end)
        return 1

    dump_size = os.path.getsize(dump_path)
    if dump_size < end:
        print("error: dump is smaller than the payload end offset")
        return 1

    print("copying dump (sparse) -> %s" % out_path)
    zero = bytes(1 << 20)
    with open(dump_path, "rb") as src, open(out_path, "wb") as dst:
        while True:
            chunk = src.read(1 << 20)
            if not chunk:
                break
            if chunk == zero[:len(chunk)]:
                dst.seek(len(chunk), os.SEEK_CUR)  # keep the file sparse
            else:
                dst.write(chunk)
        dst.truncate(dump_size)
        dst.seek(KERNEL_OFF)
        dst.write(payload)
        dst.flush()
        os.fsync(dst.fileno())

    # Verify: size, untouched head, payload placement, untouched tail.
    assert os.path.getsize(out_path) == dump_size
    with open(dump_path, "rb") as a, open(out_path, "rb") as b:
        assert sha256_range(a, 0, KERNEL_OFF) == sha256_range(b, 0, KERNEL_OFF), \
            "boot area changed!"
        assert sha256_range(b, KERNEL_OFF, len(payload)) == \
            hashlib.sha256(payload).hexdigest(), "payload mismatch!"
        assert sha256_range(a, end, dump_size - end) == \
            sha256_range(b, end, dump_size - end), "tail changed!"

    print("OK: %s" % out_path)
    print("  total size : %d bytes (same as dump)" % dump_size)
    print("  kernel area: 0x%x - 0x%x replaced with Linux payload" %
          (KERNEL_OFF, end))
    if end > 0x430000:
        print("  note: payload extends past the stock kernel slot (0x430000)")
        print("        and overwrites JA720XXX.DAT up to 0x%x." % end)
        print("        BestaWin will not boot from this image; restore by")
        print("        writing the original dump back.")
    print("  write with: dd if=%s of=<internal SD device> bs=4M status=progress"
          % os.path.basename(out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
