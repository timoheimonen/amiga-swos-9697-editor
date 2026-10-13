#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Reproduce SSBOOT's RNC unpacking and byte relocation on the host.

Inputs: an executable extracted from disk 1 (SWOS or SWOS2) and its .REL
file, each packed or raw. Output: the relocated raw image below the
repository's work/ directory, for example for a disassembler as a raw
MC68020 binary at the chosen base. SSBOOT, the game's loader, adds only one
address byte per relocation entry; relocate reproduces exactly that.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import struct

import rnc


def unpack_if_needed(data: bytes) -> bytes:
    return rnc.unpack(data) if data[:4] in (b"RNC\x01", b"RNC\x02") else data


def relocate(image: bytes, relocations: bytes, destination: int) -> bytes:
    """Apply SSBOOT's unsigned byte additions at big-endian uint32 offsets.

    The executable is assembled for $100000. The real loader selects a 512KiB
    bank. Its relocation is not general 32-bit addition and does not propagate
    carries; retain this exact behaviour even for unusual relocation entries.
    """
    if destination < 0 or destination > 0xF80000 or destination % 0x80000:
        raise ValueError("destination must be a 512KiB bank in the low 16MiB")
    if not relocations or len(relocations) % 4:
        raise ValueError("REL must be a nonempty array of big-endian uint32 offsets")
    result = bytearray(image)
    addition = ((destination - 0x100000) >> 16) & 0xFF
    for (offset,) in struct.iter_unpack(">I", relocations):
        if offset >= len(result):
            raise ValueError(f"REL offset ${offset:X} exceeds image size")
        result[offset] = (result[offset] + addition) & 0xFF
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("relocations", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--base", type=lambda n: int(n, 0), default=0x180000)
    args = parser.parse_args()
    output = args.output.resolve()
    root = Path(__file__).resolve().parents[1]
    if not output.is_relative_to(root / "work"):
        parser.error("output must be inside the repository's work/ directory")
    result = relocate(unpack_if_needed(args.image.read_bytes()),
                      unpack_if_needed(args.relocations.read_bytes()), args.base)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    print(f"{len(result)} bytes at ${args.base:X}: {output}")


if __name__ == "__main__":
    main()
