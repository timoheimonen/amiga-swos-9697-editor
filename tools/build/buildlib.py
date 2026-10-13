# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Shared helpers of the build: inputs, toolchain, linker maps and size caps.

The input is the user's own image of disk 1 [a2], read only and never a
memory dump: the image is identified by its SHA-256, SWOS2 and SWOS2.REL are
extracted and unpacked and their hashes are checked again. Every output goes
below the build directory WORK_BUILD, which a caller may point elsewhere.
Any violated check raises BuildError, which the caller reports and turns
into exit code 1.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

from adf_extract import ADF  # noqa: E402
from prepare_executable import relocate, unpack_if_needed  # noqa: E402

INCLUDE = REPO / "src/editor/include"
# The default build directory; clean_dir empties only directories below it.
WORK_BUILD = REPO / "work" / "build"
VASM = "/usr/local/bin/vasmm68k_mot"
VLINK = "/usr/local/bin/vlink"

# Identity of the reference release: disk 1 [a2], disk 2 and the executable
# SWOS2 of disk 1 with its relocation table (packed, unpacked, relocated).
DISK1_SHA256 = "b70c0db66d8c2e93f1e12aa00c5df4b465c9f29d458723130e5a946428ca92ee"
DISK2_SHA256 = "ed921246c05531a2445a3f61aee4afd493771ab79042d7c4ed210fd3f3c30d36"
SWOS2_PACKED_SHA256 = "72ba72f5c79e1158dfcc339d6ddff925ab447330f0773d248b7f2c0d653e6c8b"
SWOS2_SHA256 = "a14c565459493dc0377caf08822b0d3a6766f3ca899290dbbc17d43eee403c79"
SWOS2_REL_PACKED_SHA256 = "d7c2b55a09861fdf087a0dae72805957e16215659938b34ccd87f602cf283bf8"
SWOS2_REL_SHA256 = "d96dc4ee7ce5cef7877a5aa0bb2df22c1fbe9a30072b71f1349c114f921c9451"
SWOS2_RUNTIME_SHA256 = "7646494341c8f00a226ea1218264dc4593122e7d410d25729cbe35eb6e28bcbf"
SWOS2_BASE = 0x180000
SWOS2_SIZE = 357226


class BuildError(Exception):
    """A build input, tool run or assertion failed."""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def crc32(data: bytes) -> int:
    """CRC-32/ISO-HDLC, the integrity check used on the Amiga."""
    return zlib.crc32(data) & 0xFFFFFFFF


def check_sha256(name: str, data: bytes, expected: str) -> None:
    actual = sha256(data)
    if actual != expected:
        raise BuildError(f"{name}: SHA-256 mismatch: expected {expected}, got {actual}")


def check_cap(name: str, size: int, cap: int, *, exact: bool = False) -> None:
    """Fail loudly when a measured size exceeds (or, exact, differs from) its cap."""
    if size < 0 or (size != cap if exact else size > cap):
        relation = "must be exactly" if exact else "exceeds its cap of"
        raise BuildError(f"size check failed: {name} is {size} bytes, {relation} {cap} bytes")


# ---------------------------------------------------------------------------
# The executable
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Executable:
    """Unrelocated SWOS2, its REL table and the image SSBOOT makes of them."""
    disk1: bytes
    raw: bytes
    rel: bytes
    runtime: bytes

    def rel_offsets(self) -> list[int]:
        return [offset for (offset,) in struct.iter_unpack(">I", self.rel)]


def load_disk1(path: Path) -> bytes:
    """The image of disk 1, checked against the reference release."""
    if not path.is_file():
        raise BuildError(f"disk 1 image missing: {path}")
    data = path.read_bytes()
    check_sha256(f"disk 1 {path.name}", data, DISK1_SHA256)
    return data


def load_disk2(path: Path) -> bytes:
    """The image of disk 2, checked against the reference release."""
    if not path.is_file():
        raise BuildError(f"disk 2 image missing: {path}")
    data = path.read_bytes()
    check_sha256(f"disk 2 {path.name}", data, DISK2_SHA256)
    return data


def extract_executable(disk1: bytes) -> Executable:
    """Extract and verify the unrelocated SWOS2 and its relocation table."""
    check_sha256("disk 1", disk1, DISK1_SHA256)
    files = ADF(disk1).contents
    packed, packed_rel = files["SWOS2"], files["SWOS2.REL"]
    check_sha256("SWOS2 (packed)", packed, SWOS2_PACKED_SHA256)
    check_sha256("SWOS2.REL (packed)", packed_rel, SWOS2_REL_PACKED_SHA256)
    raw, rel = unpack_if_needed(packed), unpack_if_needed(packed_rel)
    check_sha256("SWOS2 (unrelocated)", raw, SWOS2_SHA256)
    check_sha256("SWOS2.REL", rel, SWOS2_REL_SHA256)
    runtime = relocate(raw, rel, SWOS2_BASE)
    check_sha256("SWOS2 relocated to $180000", runtime, SWOS2_RUNTIME_SHA256)
    return Executable(disk1, raw, rel, runtime)


# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
def run_tool(command: list[str], what: str) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise BuildError(f"{what}: tool not found: {command[0]}") from exc
    output = (result.stdout + result.stderr).strip()
    if result.returncode:
        raise BuildError(f"{what} failed:\n{output}")
    return output


def assemble(source: Path, output: Path, *, include: list[Path] = (),
             listing: Path | None = None, fmt: str = "vobj", cpu: str = "68020",
             include_first: list[Path] = (), defines: dict[str, int] | None = None) -> Path:
    """Assemble one Motorola-syntax source without optimizing.

    The reference CPU is the 68020; code that must also run on a plain
    68000 is assembled with cpu="68000". include_first directories are
    searched before src/editor/include.
    """
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [VASM, "-quiet", "-F" + fmt, "-m" + cpu, "-no-opt", "-o", str(output)]
    for path in [*include_first, INCLUDE, *include]:
        command += ["-I", str(path)]
    for name, value in (defines or {}).items():
        command.append(f"-D{name}={value}")
    if listing:
        command += ["-L", str(listing)]
    run_tool(command + [str(source)], f"assembling {source.name}")
    return output


def link(objects: list[Path], output: Path, origin: int, *, data_end_symbol: str = "image_end") -> "LinkMap":
    """Link objects into one raw image at origin; returns the parsed map.

    All code and data sections form one contiguous image starting at origin;
    uninitialized sections are not allowed (an image is loaded as it is).
    """
    script = output.with_suffix(".ld")
    script.write_text(
        "SECTIONS\n{\n"
        f"  . = 0x{origin:x};\n"
        f"  .image : {{ *(.text) *(.data) {data_end_symbol} = .; }}\n"
        "  .bss : { *(.bss) }\n"
        "}\n")
    map_path = output.with_suffix(".map")
    run_tool([VLINK, "-brawbin1", "-T" + str(script), "-M" + str(map_path), "-o", str(output),
              *map(str, objects)], f"linking {output.name}")
    linkmap = parse_map(map_path.read_text())
    if linkmap.sections.get(".bss", (0, 0))[1]:
        raise BuildError(f"{output.name}: uninitialized sections are not supported in a raw image")
    image = output.read_bytes() if output.exists() else b""
    expected = linkmap.symbols[data_end_symbol] - origin
    if len(image) != expected:
        raise BuildError(f"{output.name}: linked file has {len(image)} bytes, map says {expected}")
    return linkmap


@dataclass
class LinkMap:
    sections: dict[str, tuple[int, int]] = field(default_factory=dict)
    symbols: dict[str, int] = field(default_factory=dict)
    absolute: dict[str, int] = field(default_factory=dict)

    def size(self, section: str) -> int:
        try:
            return self.sections[section][1]
        except KeyError as exc:
            raise BuildError(f"section {section} missing from linker map") from exc


SECTION_LINE = re.compile(r"^\s+([0-9a-fA-F]{8})\s+(\S+)\s+\(size ([0-9a-fA-F]+)")
SYMBOL_LINE = re.compile(r"^\s+0x([0-9a-fA-F]+)\s+([A-Za-z_.$][\w.$]*):\s+\w+\s+(reloc|abs)")


def parse_map(text: str) -> LinkMap:
    """Parse the section and symbol lines of a vlink -M map file."""
    result = LinkMap()
    for line in text.splitlines():
        match = SECTION_LINE.match(line)
        if match:
            result.sections[match.group(2)] = (int(match.group(1), 16), int(match.group(3), 16))
            continue
        match = SYMBOL_LINE.match(line)
        if match:
            # Only labels of the image; equates of the include files are "abs".
            target = result.symbols if match.group(3) == "reloc" else result.absolute
            target[match.group(2)] = int(match.group(1), 16)
    if not result.sections:
        raise BuildError("linker map has no sections")
    return result


EQU_LINE = re.compile(r"^([A-Za-z_]\w*)\s+equ\s", re.MULTILINE)


def probe_constants(files: list[Path], work: Path) -> dict[str, int]:
    """Evaluate every equ of the given include files with the assembler itself."""
    names = []
    for path in files:
        names += EQU_LINE.findall(path.read_text())
    source = work / "constants_probe.s"
    work.mkdir(parents=True, exist_ok=True)
    lines = [f'        include "{path.name}"' for path in files]
    lines += [f"        dc.l {name}" for name in names]
    source.write_text("\n".join(lines) + "\n")
    binary = assemble(source, work / "constants_probe.bin", include=[p.parent for p in files], fmt="bin")
    values = struct.unpack(f">{len(names)}I", binary.read_bytes())
    return dict(zip(names, values))


CONSTANT_INCLUDES = ("swos2.i", "slave.i", "layout.i", "editor.i", "work.i", "ui.i", "dialog.i", "team.i",
                     "tactic.i", "definition.i", "database.i")


def layout_constants(work: Path) -> dict[str, int]:
    return probe_constants([INCLUDE / name for name in CONSTANT_INCLUDES], work)


# ---------------------------------------------------------------------------
# Budgets
# ---------------------------------------------------------------------------
def menu_page_bytes(entries: int, text_buffers: int, caps: dict[str, int]) -> int:
    """Arena bytes a native page needs, including the parser's entry reserve."""
    return (caps["MENU_HEADER_SIZE"] + entries * caps["MENU_ENTRY_SIZE"]
            + text_buffers * caps["MENU_TEXT_BUFFER_SIZE"] + caps["MENU_PARSER_RESERVE"])


def check_menu_page(name: str, entries: int, text_buffers: int, caps: dict[str, int]) -> int:
    need = menu_page_bytes(entries, text_buffers, caps)
    if need > caps["MENU_PAGE_LIMIT"]:
        raise BuildError(f"page check failed: {name} needs {need} arena bytes "
                         f"({entries} entries, {text_buffers} text buffers), "
                         f"limit {caps['MENU_PAGE_LIMIT']}")
    return need


def count_text_buffers(template: dict) -> int:
    """Writable text buffers of a template decoded by menu_template.decode
    (opcode 8 with a pointer below $100, or opcode 22)."""
    return sum(entry["content_kind"] == 2 and entry["content_value"] == 0xFFFFFFFF
               for entry in template["entries"])


# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
def clean_dir(path: Path) -> Path:
    """Empty a build output directory below WORK_BUILD."""
    path = path.resolve()
    if not path.is_relative_to(WORK_BUILD.resolve()):
        raise BuildError(f"refusing to clean a directory outside the build directory "
                         f"{WORK_BUILD}: {path}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    return path


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n")


def address_symbols(constants: dict[str, int]) -> dict[str, int]:
    """Names of swos2.i that are addresses: lowercase by convention."""
    return {name: value for name, value in constants.items() if name[0].islower()}


# ---------------------------------------------------------------------------
# Relocatable images
# ---------------------------------------------------------------------------
FIXUP_PROBE_DELTA = 0x10000


def infer_fixups(low: bytes, high: bytes, delta: int = FIXUP_PROBE_DELTA,
                 limit: int | None = None) -> list[int]:
    """Offsets of the BE32 fields that point into an image linked at two origins.

    low is linked at 0, high at delta. Every difference must be an aligned
    internal pointer (below limit, default the image length; the editor's
    pointers may reach its working data) that grows by exactly delta;
    anything else is rejected.
    """
    limit = len(low) if limit is None else limit
    if len(low) != len(high):
        raise BuildError("linking at two origins changed the image size")
    offsets = []
    index = 0
    while index < len(low):
        if low[index] == high[index]:
            index += 1
            continue
        start = index - 1  # +$10000 changes byte 1 of a low-address BE32
        if start < 0 or start + 4 > len(low) or start % 2:
            raise BuildError(f"unexplained origin difference at image offset ${index:X}")
        a, b = (struct.unpack_from(">I", data, start)[0] for data in (low, high))
        if b != a + delta or a >= limit:
            raise BuildError(f"origin difference at ${start:X} is not an internal pointer")
        offsets.append(start)
        index = start + 4
    check = bytearray(low)
    for offset in offsets:
        struct.pack_into(">I", check, offset, struct.unpack_from(">I", check, offset)[0] + delta)
    if check != high:
        raise BuildError("fixups do not reproduce the image linked at the second origin")
    return offsets


def infer_imports(normal: bytes, shifted: bytes, low: int, high: int,
                  delta: int = FIXUP_PROBE_DELTA) -> list[int]:
    """Offsets of the BE32 fields that hold an address of low..high.

    normal and shifted are the same image linked at the same origin, the
    second assembled with every address of low..high moved up by delta.
    """
    if len(normal) != len(shifted):
        raise BuildError("shifting the imported addresses changed the image size")
    offsets = []
    index = 0
    while index < len(normal):
        if normal[index] == shifted[index]:
            index += 1
            continue
        start = index - 1  # +$10000 changes byte 1 of the BE32 address
        if start < 0 or start + 4 > len(normal) or start % 2:
            raise BuildError(f"unexplained import difference at image offset ${index:X}")
        a, b = (struct.unpack_from(">I", data, start)[0] for data in (normal, shifted))
        if b != a + delta or not low <= a <= high:
            raise BuildError(f"import difference at ${start:X} is not an address of the executable")
        offsets.append(start)
        index = start + 4
    check = bytearray(normal)
    for offset in offsets:
        struct.pack_into(">I", check, offset, struct.unpack_from(">I", check, offset)[0] + delta)
    if check != shifted:
        raise BuildError("imports do not reproduce the shifted image")
    return offsets


def shifted_constants(source: Path, constants: dict[str, int], low: int, high: int,
                      delta: int = FIXUP_PROBE_DELTA) -> str:
    """An include file defining every equate of source literally, with the
    values in low..high moved up by delta (for infer_imports)."""
    names = EQU_LINE.findall(source.read_text())
    lines = [f"; Generated from {source.name}: addresses ${low:X}..${high:X} moved by ${delta:X}."]
    for name in names:
        value = constants[name]
        if low <= value <= high:
            value += delta
        lines.append(f"{name} equ ${value:X}")
    return "\n".join(lines) + "\n"


def relocate_image(image: bytes, fixups: list[int], base: int) -> bytes:
    moved = bytearray(image)
    for offset in fixups:
        struct.pack_into(">I", moved, offset, struct.unpack_from(">I", moved, offset)[0] + base)
    return bytes(moved)
