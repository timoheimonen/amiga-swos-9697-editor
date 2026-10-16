# SWOS 96-97 In-Game Editors V0.91b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Patch manifest: what the build changes in the relocated SWOS2, as data.

A manifest is a JSON file:

    {"description": "...",
     "patches": [
       {"name": "file_driver_call", "table": "base",
        "address": "0x1805C0", "length": 6,
        "expected_sha256": "<SHA-256 of the original runtime bytes>",
        "replacement": {"jmp": "slave_file_driver", "image": "slave"},
        "note": "..."},
       {"name": "main_template_operand", "table": "runtime",
        "address": "0x1A0432", "length": 4, "expected": "<hex of the original bytes>",
        "replacement": {"pointer": "WORK_MAIN_MENU", "image": "editor"}}]}

* address is the runtime address with SWOS2 at $180000 (file offset =
  address - $180000).
* The expected original bytes are given literally ("expected", hex, at most 16
  bytes) or as "expected_sha256"; the manifests of the release give every
  range as expected_sha256, so they hold no byte of the game. Both are
  checked against the unrelocated SWOS2 after SSBOOT's single-byte REL
  relocation has been applied to it.
* table "base" patches form the WHDLoad slave's base patch table, applied by
  the slave before the game starts; table "runtime" patches form the
  editor's hook table, installed by the slave after the editor has been
  verified; both all or nothing. The format also supports table "static":
  patches inside a fixed window (resolve's static_window) that
  apply_static_to_raw puts into the unrelocated file itself; the release
  build uses only "base" and "runtime".
* replacement is {"binary": NAME} (all bytes of a linked fixed-address binary),
  {"pointer": SYMBOL, "image": NAME} (a BE32 pointer to SYMBOL inside a
  relocatable image, stored as an image offset with one fixup),
  {"jsr": SYMBOL, "image": NAME} or {"jmp": SYMBOL, "image": NAME} (JSR or JMP
  abs.l to SYMBOL in the image, six bytes, the address with one fixup), or
  {"template": SYMBOL, "image": NAME, "fixups": [OFFSET, ...]} (length bytes
  copied from the image at SYMBOL; the listed BE32 fields hold image offsets
  and get the image base added when the table is applied).

Overlapping patches, patches outside the image, wrong lengths and expected
bytes that do not match are rejected.

Both tables share one binary layout (big-endian), entries sorted by address:

    dc.w count
    count times:
      dc.l address          runtime address
      dc.w length           bytes replaced
      dc.l expected_crc32   CRC-32/ISO-HDLC of the original bytes
      dc.w fixups           number of image-relative BE32 fields
      dc.w offset[fixups]   their offsets inside the replacement
      dc.b replacement[length], padded to an even length

An applier computes the CRC-32 of the bytes at every address first and writes
nothing unless all match; it adds the image base to each fixup field. The
tables carry checksums, not original bytes.
"""
from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path

from buildlib import BuildError, Executable, crc32, relocate, sha256

LITERAL_MAX = 16
TABLES = ("static", "base", "runtime")
IMAGE_KINDS = ("pointer", "jsr", "jmp", "template")


@dataclass(frozen=True)
class Patch:
    name: str
    table: str
    address: int
    length: int
    expected: bytes | None
    expected_sha256: str | None
    replacement: dict
    note: str = ""


@dataclass
class Resolved:
    patch: Patch
    original: bytes
    replacement: bytes
    fixups: list[int] = field(default_factory=list)
    rel_offsets: list[int] = field(default_factory=list)

    @property
    def end(self) -> int:
        return self.patch.address + self.patch.length


def parse_patch(item: dict) -> Patch:
    try:
        name, table = item["name"], item["table"]
        address = int(item["address"], 16) if isinstance(item["address"], str) else int(item["address"])
        length = int(item["length"])
        replacement = item["replacement"]
    except (KeyError, TypeError, ValueError) as exc:
        raise BuildError(f"manifest entry is incomplete: {item!r}") from exc
    if table not in TABLES:
        raise BuildError(f"{name}: table must be one of {TABLES}")
    if length <= 0:
        raise BuildError(f"{name}: length must be positive")
    expected = item.get("expected")
    expected_hash = item.get("expected_sha256")
    if (expected is None) == (expected_hash is None):
        raise BuildError(f"{name}: give exactly one of expected or expected_sha256")
    if expected is not None:
        expected = bytes.fromhex(expected)
        if len(expected) != length:
            raise BuildError(f"{name}: expected bytes have {len(expected)} bytes, length is {length}")
        if length > LITERAL_MAX:
            raise BuildError(f"{name}: literal expected bytes are limited to {LITERAL_MAX}; "
                             "use expected_sha256")
    allowed = [{"binary"}, *({kind, "image"} for kind in IMAGE_KINDS[:3]), {"template", "image", "fixups"}]
    if not isinstance(replacement, dict) or set(replacement) not in allowed:
        raise BuildError(f"{name}: replacement must be {{binary}}, {{pointer|jsr|jmp, image}} "
                         "or {template, image, fixups}")
    return Patch(name, table, address, length, expected, expected_hash, replacement,
                 item.get("note", ""))


def load_manifest(path: Path) -> list[Patch]:
    try:
        document = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise BuildError(f"cannot read manifest {path}: {exc}") from exc
    patches = [parse_patch(item) for item in document.get("patches", [])]
    names = [patch.name for patch in patches]
    if len(set(names)) != len(names):
        raise BuildError("manifest has duplicate patch names")
    return patches


def resolve(patches: list[Patch], exe: Executable, *, static_window: tuple[int, int] | None = None,
            binaries: dict[str, bytes] | None = None,
            images: dict[str, dict[str, int]] | None = None,
            image_bytes: dict[str, bytes] | None = None,
            base: int = 0x180000) -> list[Resolved]:
    """Check every patch against SWOS2 and build its replacement bytes.

    images maps an image name to its symbols (offsets from the image start);
    image_bytes to its linked bytes, needed by "template" replacements.
    """
    binaries, images, image_bytes = binaries or {}, images or {}, image_bytes or {}
    rel = sorted(exe.rel_offsets())
    resolved = []
    for patch in patches:
        start = patch.address - base
        if start < 0 or start + patch.length > len(exe.runtime):
            raise BuildError(f"{patch.name}: ${patch.address:X}+{patch.length} lies outside SWOS2")
        original = exe.runtime[start:start + patch.length]
        if patch.expected is not None and original != patch.expected:
            raise BuildError(f"{patch.name}: original bytes at ${patch.address:X} are "
                             f"{original.hex()}, manifest expects {patch.expected.hex()}")
        if patch.expected_sha256 is not None and sha256(original) != patch.expected_sha256:
            raise BuildError(f"{patch.name}: original bytes at ${patch.address:X} do not match "
                             "the manifest's expected_sha256")
        spec = patch.replacement
        if "binary" in spec:
            if spec["binary"] not in binaries:
                raise BuildError(f"{patch.name}: binary {spec['binary']} was not built")
            replacement, fixups = binaries[spec["binary"]], []
        else:
            kind = next(kind for kind in IMAGE_KINDS if kind in spec)
            symbols = images.get(spec["image"])
            if symbols is None or spec[kind] not in symbols:
                raise BuildError(f"{patch.name}: symbol {spec[kind]} not in image {spec['image']}")
            target = symbols[spec[kind]]
            if kind == "pointer":
                replacement, fixups = struct.pack(">I", target), [0]
            elif kind == "jsr":
                replacement, fixups = struct.pack(">HI", 0x4EB9, target), [2]
            elif kind == "jmp":
                replacement, fixups = struct.pack(">HI", 0x4EF9, target), [2]
            else:
                data = image_bytes.get(spec["image"])
                if data is None or target + patch.length > len(data):
                    raise BuildError(f"{patch.name}: template {spec['template']} lies outside "
                                     f"image {spec['image']}")
                replacement, fixups = data[target:target + patch.length], sorted(spec["fixups"])
                for offset in fixups:
                    if offset < 0 or offset % 2 or offset + 4 > patch.length:
                        raise BuildError(f"{patch.name}: template fixup {offset} is not an even "
                                         "BE32 field inside the replacement")
        if len(replacement) != patch.length:
            raise BuildError(f"{patch.name}: replacement has {len(replacement)} bytes, "
                             f"manifest length is {patch.length}")
        if patch.table == "static":
            if static_window is None:
                raise BuildError(f"{patch.name}: static patches need a static window")
            low, high = static_window
            if patch.address < low or patch.address + patch.length > high:
                raise BuildError(f"{patch.name}: static patches must lie in the static window "
                                 f"${low:X}..${high:X}")
            if fixups:
                raise BuildError(f"{patch.name}: static patches cannot hold image pointers")
        inside = [base + offset for offset in rel if start <= offset < start + patch.length]
        resolved.append(Resolved(patch, original, replacement, fixups, inside))
    ordered = sorted(resolved, key=lambda item: item.patch.address)
    for first, second in zip(ordered, ordered[1:]):
        if second.patch.address < first.end:
            raise BuildError(f"patches overlap: {first.patch.name} (${first.patch.address:X}.."
                             f"${first.end:X}) and {second.patch.name} (${second.patch.address:X})")
    return ordered


def check_disjoint(first: list[Resolved], second: list[Resolved]) -> None:
    """Patches of two tables (the slave's base table and the editor's hook
    table) must not touch the same bytes."""
    for a in first:
        for b in second:
            if a.patch.address < b.end and b.patch.address < a.end:
                raise BuildError(f"patches overlap: {a.patch.name} (${a.patch.address:X}..${a.end:X}) "
                                 f"and {b.patch.name} (${b.patch.address:X}..${b.end:X})")


def table_bytes(entries: list[Resolved]) -> bytes:
    """Encode resolved patches in the shared table layout described above."""
    out = bytearray(struct.pack(">H", len(entries)))
    for item in sorted(entries, key=lambda entry: entry.patch.address):
        out += struct.pack(">IHIH", item.patch.address, item.patch.length,
                           crc32(item.original), len(item.fixups))
        out += b"".join(struct.pack(">H", offset) for offset in item.fixups)
        out += item.replacement + bytes(len(item.replacement) & 1)
    return bytes(out)


def decode_table(data: bytes) -> list[dict]:
    """Inverse of table_bytes, for checks and inspection."""
    (count,), cursor, result = struct.unpack_from(">H", data), 2, []
    for _ in range(count):
        address, length, expected, fixups = struct.unpack_from(">IHIH", data, cursor)
        cursor += 12
        offsets = list(struct.unpack_from(f">{fixups}H", data, cursor))
        cursor += 2 * fixups
        replacement = data[cursor:cursor + length]
        cursor += length + (length & 1)
        result.append({"address": address, "length": length, "expected_crc32": expected,
                       "fixups": offsets, "replacement": replacement})
    if cursor != len(data):
        raise BuildError("patch table has trailing or missing bytes")
    return result


def table_include(entries: list[Resolved], table: str) -> str:
    """Assembler equates for every patch of a table (address, length, CRC)."""
    lines = [f"; Generated from the patch manifest: {table} table. Do not edit."]
    for item in entries:
        prefix = "PATCH_" + item.patch.name.upper()
        lines += [f"{prefix}_ADDRESS equ ${item.patch.address:X}",
                  f"{prefix}_LENGTH equ {item.patch.length}",
                  f"{prefix}_CRC32 equ ${crc32(item.original):08X}"]
    lines.append(f"PATCH_{table.upper()}_COUNT equ {len(entries)}")
    return "\n".join(lines) + "\n"


def apply_runtime(runtime: bytes, entries: list[Resolved], *, image_base: int = 0,
                  base: int = 0x180000) -> bytes:
    """The relocated SWOS2 after applying entries the way an applier does."""
    result = bytearray(runtime)
    for item in entries:
        if crc32(bytes(result[item.patch.address - base:item.end - base])) != crc32(item.original):
            raise BuildError(f"{item.patch.name}: CRC-32 check of the original bytes failed")
    for item in entries:
        data = bytearray(item.replacement)
        for offset in item.fixups:
            struct.pack_into(">I", data, offset, struct.unpack_from(">I", data, offset)[0] + image_base)
        result[item.patch.address - base:item.end - base] = data
    return bytes(result)


def apply_static_to_raw(exe: Executable, entries: list[Resolved], *, base: int = 0x180000) -> bytes:
    """Put static patches into the unrelocated SWOS2 itself.

    SSBOOT later adds the REL addend to every REL-listed byte, so each such
    byte inside a window is stored with the addend subtracted (once per REL
    occurrence, modulo 256). The whole image is relocated again to prove that
    the result equals the patched runtime image exactly.
    """
    addend = ((base - 0x100000) >> 16) & 0xFF
    raw = bytearray(exe.raw)
    for item in entries:
        if item.patch.table != "static":
            raise BuildError(f"{item.patch.name}: only static patches can be put into the file")
        window = bytearray(item.replacement)
        for address in item.rel_offsets:
            window[address - item.patch.address] = (window[address - item.patch.address] - addend) & 0xFF
        raw[item.patch.address - base:item.end - base] = window
    expected = apply_runtime(exe.runtime, entries, base=base)
    if relocate(bytes(raw), exe.rel, base) != expected:
        raise BuildError("relocating the patched SWOS2 does not give the intended runtime image")
    return bytes(raw)


def report(entries: list[Resolved]) -> list[dict]:
    return [{
        "name": item.patch.name, "table": item.patch.table,
        "address": f"${item.patch.address:X}", "length": item.patch.length,
        "file_offset": item.patch.address - 0x180000,
        "original_hex": item.original.hex(), "original_crc32": f"{crc32(item.original):08X}",
        "replacement_hex": item.replacement.hex(), "fixups": item.fixups,
        "rel_bytes_inside": [f"${address:X}" for address in item.rel_offsets],
        "note": item.patch.note} for item in entries]
