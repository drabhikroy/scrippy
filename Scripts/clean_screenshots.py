#!/usr/bin/env python3
"""Prepares README screenshots so they carry nothing but the picture.

A macOS screenshot holds the display's color profile, an XMP block, and
Apple's own chunks. Each file is first converted to sRGB with sips, so the
colors stay right once the profile is gone, and then rewritten in place with
only the chunks needed to draw it.

    python3 Scripts/clean_screenshots.py Assets/screenshots/*.png
"""

import platform
import struct
import subprocess
import sys
import zlib
from pathlib import Path

KEEP = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"}
SIGNATURE = b"\x89PNG\r\n\x1a\n"
SRGB = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"


def chunks(data):
    position = len(SIGNATURE)
    while position < len(data):
        (length,) = struct.unpack(">I", data[position:position + 4])
        kind = data[position + 4:position + 8]
        yield kind, data[position + 8:position + 8 + length]
        position += 12 + length


def strip(path):
    data = path.read_bytes()
    if not data.startswith(SIGNATURE):
        raise ValueError(f"{path} is not a PNG file")
    out = bytearray(SIGNATURE)
    for kind, body in chunks(data):
        if kind in KEEP:
            out += struct.pack(">I", len(body)) + kind + body
            out += struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    path.write_bytes(bytes(out))


def main(paths):
    if not paths:
        print(__doc__.strip())
        return 1
    for name in paths:
        path = Path(name)
        if platform.system() == "Darwin" and Path(SRGB).exists():
            subprocess.run(["/usr/bin/sips", "--matchTo", SRGB, str(path)],
                           check=True, stdout=subprocess.DEVNULL)
        strip(path)
        print(f"Cleaned {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
