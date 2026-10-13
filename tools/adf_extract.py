#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Read-only OFS/FFS floppy extractor, preserving block provenance in JSON.

Input: a DOS0/DOS1 DD or HD ADF, which is only read. Outputs: exact files and an
optional JSON inventory. No dependency beyond Python 3.

Example: python3 tools/adf_extract.py 'Disk 1.adf' extracted/disk1 \
    --inventory inventory/disk1.json --unpacked unpacked/disk1
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct

BLOCK_SIZE = 512
MASK = 0xFFFFFFFF


class ADFError(ValueError):
    """Invalid or unsupported filesystem structure."""


def words(data):
    return struct.unpack(">" + "I" * (len(data) // 4), data)


def boot_checksum_valid(data):
    total = 0
    for value in words(data[:1024]):
        total += value
        total = (total & MASK) + (total >> 32)
    return total == MASK


def name_hash(name):
    """Classic DOS0/DOS1 filename hash; fold ASCII lowercase only."""
    encoded = name.encode("latin1")
    result = len(encoded)
    for byte in encoded:
        result = (result * 13 + (byte - 32 if 97 <= byte <= 122 else byte)) & 0x7FF
    return result % 72


class ADF:
    """Validated in-memory filesystem; input bytes are never modified."""

    def __init__(self, data, source="<bytes>", *, native_swos=False):
        self.data = bytes(data)
        self.source = str(source)
        self.native_swos = native_swos
        if len(data) not in (901120, 1802240):
            raise ADFError("expected a DD (901120) or HD (1802240) ADF")
        if data[:3] != b"DOS" or data[3] not in (0, 1):
            raise ADFError("only standard DOS0/OFS and DOS1/FFS are supported")
        self.ffs = bool(data[3] & 1)
        self.block_count = len(data) // BLOCK_SIZE
        # Floppy root position is geometric, not dependent on bootability.
        # SWOS's formatter leaves repeated DOS0 words in the boot area.
        self.root = self.block_count // 2
        self.claims = {0: "boot", 1: "boot"}
        self.checked_blocks = set()
        self.entries = []
        self.contents = {}
        self.unpacked_metadata = {}
        root = self.checked(self.root, 2, 1)
        if root[3] != 72:
            raise ADFError("root hash-table size is not 72")
        self.volume_name = self.name(self.root)
        self.claim(self.root, "root")
        self.walk(self.root, "")
        self.entries.sort(key=lambda item: item["path"].lower())
        self.bitmap_blocks = [p for p in root[79:104] if p]
        if root[104]:
            raise ADFError("bitmap extensions are unsupported on floppy images")
        self.free_blocks = []
        for i, block in enumerate(self.bitmap_blocks):
            self.claim(block, "bitmap")
            bits = self.checked(block)
            for bit in range(127 * 32):
                number = 2 + i * 127 * 32 + bit
                if number >= self.block_count:
                    break
                if bits[1 + bit // 32] & (1 << (bit % 32)):
                    self.free_blocks.append(number)
        if len(self.bitmap_blocks) != (self.block_count - 2 + 4063) // 4064:
            raise ADFError("incomplete bitmap coverage")
        self.bitmap_valid = root[78] == MASK
        if self.bitmap_valid:
            conflict = sorted(set(self.free_blocks) & self.claims.keys())
            if conflict:
                raise ADFError(f"referenced blocks marked free: {conflict}")
        allocated = set(range(2, self.block_count)) - set(self.free_blocks)
        self.unreferenced_allocated = sorted(allocated - self.claims.keys())

    @classmethod
    def from_path(cls, path, *, native_swos=False):
        path = Path(path)
        return cls(path.read_bytes(), path, native_swos=native_swos)

    def block(self, number):
        if not 2 <= number < self.block_count:
            raise ADFError(f"block pointer {number} outside filesystem")
        return self.data[number * 512:(number + 1) * 512]

    def checked(self, number, primary=None, secondary=None):
        result = words(self.block(number))
        if sum(result) & MASK:
            raise ADFError(f"checksum failure in block {number}")
        if primary is not None and result[0] != primary:
            raise ADFError(f"block {number}: expected type {primary}, got {result[0]}")
        if secondary is not None and result[127] != secondary & MASK:
            raise ADFError(f"block {number}: wrong secondary type")
        self.checked_blocks.add(number)
        return result

    def claim(self, number, owner):
        self.block(number)
        if number in self.claims:
            raise ADFError(f"block {number} reused by {owner} and {self.claims[number]}")
        self.claims[number] = owner

    def name(self, number):
        block = self.block(number)
        length = block[432]
        if not 1 <= length <= 30:
            raise ADFError(f"invalid name length in block {number}")
        name = block[433:433 + length].decode("latin1")
        if name in (".", "..") or any(c in name for c in "/:\\\x00"):
            raise ADFError(f"unsafe name in block {number}")
        return name

    def walk(self, directory, prefix):
        table = words(self.block(directory))[6:78]
        names = set()
        for bucket, pointer in enumerate(table):
            while pointer:
                self.claim(pointer, prefix + "directory entry")
                header = self.checked(pointer, 2)
                if header[1] != pointer or header[125] != directory:
                    raise ADFError(f"header/parent mismatch in block {pointer}")
                name = self.name(pointer)
                if name_hash(name) != bucket:
                    raise ADFError(f"wrong hash bucket for {name} in block {pointer}")
                if name.upper() in names:
                    raise ADFError(f"duplicate filename in directory {directory}")
                names.add(name.upper())
                path = prefix + name
                entry = {"path": path, "header_block": pointer,
                         "header_adf_offset": pointer * 512,
                         "parent_block": directory, "protection": header[80]}
                if header[127] == 2:
                    entry.update(kind="directory")
                    self.entries.append(entry)
                    self.walk(pointer, path + "/")
                elif header[127] == MASK - 2:
                    payload, blocks, extensions, convention = self.read_file(pointer, path)
                    self.contents[path] = payload
                    entry.update(kind="file", size=len(payload),
                                 sha256=hashlib.sha256(payload).hexdigest(),
                                 data_blocks=blocks, extension_blocks=extensions,
                                 extension_convention=convention)
                    self.entries.append(entry)
                else:
                    raise ADFError(f"unsupported entry type {header[127]} for {path}")
                pointer = header[124]

    def read_file(self, header_block, path):
        header = words(self.block(header_block))
        size = header[81]
        block = header_block
        blocks = []
        data_owners = []
        extensions = []
        convention = None
        previous_pointers = None
        while block:
            if block != header_block:
                self.claim(block, path + " extension")
                extensions.append(block)
            meta = self.checked(block, 2 if block == header_block else 16, -3)
            if meta[1] != block:
                raise ADFError(f"self pointer mismatch in block {block}")
            owner = header_block
            if block != header_block:
                if meta[125] == header_block:
                    block_convention = "standard"
                elif self.native_swos and not self.ffs and meta[125] == header[125]:
                    block_convention = "native_swos"
                    owner = block
                else:
                    raise ADFError(f"extension parent mismatch in block {block}")
                if convention is not None and convention != block_convention:
                    raise ADFError(f"mixed extension conventions in {path}")
                convention = block_convention
            if meta[2] > 72:
                raise ADFError(f"too many data pointers in block {block}")
            pointers = list(reversed(meta[6:78]))
            if any(pointers[meta[2]:]):
                # The native writer reuses its header buffer without clearing
                # slots beyond high_seq. Accept only the exact prior table's
                # residual slots, never arbitrary hidden block pointers.
                if not (self.native_swos and convention == "native_swos"
                        and previous_pointers is not None
                        and pointers[meta[2]:] == previous_pointers[meta[2]:]):
                    raise ADFError(f"unused pointer slots are nonzero in block {block}")
            for pointer in pointers[:meta[2]]:
                self.claim(pointer, path + " data")
                blocks.append(pointer)
                data_owners.append(owner)
            previous_pointers = pointers
            block = meta[126]
        capacity = 512 if self.ffs else 488
        if len(blocks) != (size + capacity - 1) // capacity:
            raise ADFError(f"{path}: data pointer count does not match byte size")
        payload = bytearray()
        if not self.ffs and header[4] != (blocks[0] if blocks else 0):
            raise ADFError(f"{path}: first_data disagrees with pointer table")
        for index, block in enumerate(blocks):
            raw = self.block(block)
            if self.ffs:
                payload.extend(raw)
            else:
                meta = self.checked(block, 8)
                expected_next = blocks[index + 1] if index + 1 < len(blocks) else 0
                if meta[1] != data_owners[index] or meta[2] != index + 1:
                    raise ADFError(f"{path}: OFS owner/sequence mismatch at {block}")
                if meta[4] != expected_next:
                    raise ADFError(f"{path}: OFS data chain differs from header tables")
                length = min(488, size - len(payload))
                if meta[3] != length:
                    raise ADFError(f"{path}: OFS data length mismatch at {block}")
                payload.extend(raw[24:24 + length])
        return bytes(payload[:size]), blocks, extensions, convention or "none"

    def inventory(self):
        return {"source": self.source, "sha256": hashlib.sha256(self.data).hexdigest(),
                "size": len(self.data), "filesystem": "FFS" if self.ffs else "OFS",
                "native_swos_enabled": self.native_swos,
                "volume_name": self.volume_name, "root_block": self.root,
                "boot_root_field": words(self.data[:12])[2],
                "boot_checksum_valid": boot_checksum_valid(self.data),
                "boot_sha256": hashlib.sha256(self.data[:1024]).hexdigest(),
                "bitmap_blocks": self.bitmap_blocks, "bitmap_valid": self.bitmap_valid,
                "free_block_count": len(self.free_blocks),
                "unreferenced_allocated_blocks": self.unreferenced_allocated,
                "checked_block_count": len(self.checked_blocks),
                "file_count": len(self.contents),
                "directory_count": sum(e["kind"] == "directory" for e in self.entries),
                "total_file_bytes": sum(map(len, self.contents.values())),
                "entries": [dict(entry, **self.unpacked_metadata.get(entry["path"], {}))
                            for entry in self.entries]}

    def extract(self, destination, *, unpack_rnc=False):
        destination = Path(destination).resolve()
        contents = self.contents
        if unpack_rnc:
            from rnc import unpack
            contents = {}
            for name, payload in self.contents.items():
                packed = payload[:3] == b"RNC" and len(payload) >= 4
                result = unpack(payload) if packed else payload
                contents[name] = result
                self.unpacked_metadata[name] = {
                    "compression": f"RNC{payload[3]}" if packed else "none",
                    "unpacked_size": len(result),
                    "unpacked_sha256": hashlib.sha256(result).hexdigest()}
        for entry in self.entries:
            target = destination / entry["path"]
            if not target.resolve().is_relative_to(destination):
                raise ADFError("output symlink escapes destination")
            if entry["kind"] == "directory":
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(contents[entry["path"]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--unpacked", type=Path,
                        help="also write an RNC-decoded mirror (validating both CRCs)")
    parser.add_argument("--native-swos", action="store_true",
                        help="allow the game's nonstandard OFS extension ownership layout")
    args = parser.parse_args()
    # The image is only read: no output may replace it.
    image = args.image.resolve()
    for output in (args.destination, args.inventory, args.unpacked):
        if output is not None and output.resolve() == image:
            parser.error("input and output must be different paths")
    try:
        disk = ADF.from_path(args.image, native_swos=args.native_swos)
        disk.extract(args.destination)
        if args.unpacked:
            disk.extract(args.unpacked, unpack_rnc=True)
        inventory = disk.inventory()
        if args.inventory:
            args.inventory.parent.mkdir(parents=True, exist_ok=True)
            args.inventory.write_text(json.dumps(inventory, indent=2) + "\n")
        print(f"{disk.volume_name}: {len(disk.contents)} files, "
              f"{inventory['total_file_bytes']} bytes -> {args.destination}")
    except (ValueError, OSError) as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    main()
