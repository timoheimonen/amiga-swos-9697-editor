#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Assemble the WHDLoad slave of SWOS 96-97 and make its Workbench icon.

Usage: python3 whdload/build.py GENERATED_DIR -o SWOS.slave [--vasm PATH] [--vlink PATH]

GENERATED_DIR holds the inputs that depend on the user's own SWOS2 and on
the editor build: slave_gen.i (CRC-32 values of SWOS2, SWOS2.REL and the
editor file, the SWOS2 identity) and base_table.bin (the base patch table).
The slave is assembled with vasmm68k_mot (Motorola syntax) and linked with
vlink into one position-independent code hunk without relocations; linking
at two origins must give the same bytes.

The module also writes the install's icon: a Workbench project icon whose
default tool is WHDLoad, with the tool types SLAVE=, PRELOAD, NOWRITECACHE
and WRITEDELAY=10.
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'src' / 'slave.s'
EDITOR_INCLUDE = ROOT.parent / 'src' / 'editor' / 'include'
SLAVE_NAME = 'SWOS.slave'
ICON_NAME = 'SWOS.info'
EDITOR_NAME = 'Editor.bin'
SAVE_DIRECTORY = 'data'
PROBE_ORIGIN = 0x10000

HUNK_HEADER, HUNK_CODE, HUNK_END = 0x3F3, 0x3E9, 0x3F2
SYMBOL_LINE = re.compile(r'^\s+0x([0-9a-fA-F]+)\s+([A-Za-z_.$][\w.$]*):\s+\w+\s+(reloc|abs)')

# The icon's picture: '.' background (colour 0), 'k' black (1), 'w' white (2),
# 'b' blue (3) in the standard Workbench palette: a football, round on the
# default 640x256 Workbench screen, whose pixels are about twice as tall as wide.
ICON_PICTURE = '''\
........kkkkkkkkkk........
.....kkkwwkkkkkkwwkkk.....
...kkwwwwwwwkkwwwwwwwkk...
..kkwwwwwwwwkkwwwwwwwwkk..
.kkkkwwwwwwwkkwwwwwwwkkkk.
kkkkkwwwwwwkkkkwwwwwwkkkkk
kkkkwwwwwkkkkkkkkwwwwwkkkk
kwwwwwwwwkkkkkkkkwwwwwwwwk
kwwwwwwwwwkkkkkkwwwwwwwwwk
.kwwwwwwwkwwwwwwkwwwwwwwk.
..kwwwkkkwwwwwwwwkkkwwwk..
...kkkkkkkwwwwwwkkkkkkk...
.....kkkkkwwwwwwkkkkk.....
........kkkkkkkkkk........'''
# PRELOAD keeps the disk images in memory; NOWRITECACHE writes a save to the
# hard disk at once; WRITEDELAY=10 waits 0.2 seconds after a write instead of
# WHDLoad's default of 3 seconds.
ICON_TOOLTYPES = ['PRELOAD', 'NOWRITECACHE', 'WRITEDELAY=10']


class SlaveError(Exception):
    """Assembling or checking the slave failed."""


def run(command: list[str], what: str) -> None:
    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise SlaveError(f'{what}: tool not found: {command[0]}') from exc
    if result.returncode:
        raise SlaveError(f'{what} failed:\n{(result.stdout + result.stderr).strip()}')


def assemble(generated: Path, work: Path, origin: int = 0, *, vasm: str = 'vasmm68k_mot',
             vlink: str = 'vlink', defines: dict[str, int] | None = None) -> tuple[bytes, dict[str, int]]:
    """Assemble and link the slave at origin. Returns the raw code and the
    offsets of its labels from the start of the slave."""
    work.mkdir(parents=True, exist_ok=True)
    obj = work / 'slave.o'
    run([vasm, '-quiet', '-Fvobj', '-m68020', '-no-opt', '-o', str(obj),
         '-I', str(generated), '-I', str(ROOT / 'src'), '-I', str(EDITOR_INCLUDE),
         *(f'-D{name}={value}' for name, value in (defines or {}).items()),
         str(SOURCE)], 'assembling the slave')
    script = work / 'slave.ld'
    script.write_text('SECTIONS\n{\n'
                      f'  . = 0x{origin:x};\n'
                      '  .image : { *(.text) *(.data) slave_end = .; }\n'
                      '  .bss : { *(.bss) }\n}\n')
    binary, map_path = work / f'slave-{origin:x}.bin', work / f'slave-{origin:x}.map'
    run([vlink, '-brawbin1', '-T' + str(script), '-M' + str(map_path), '-o', str(binary), str(obj)],
        'linking the slave')
    symbols = {}
    for line in map_path.read_text().splitlines():
        match = SYMBOL_LINE.match(line)
        if match and match.group(3) == 'reloc':
            symbols[match.group(2)] = int(match.group(1), 16) - origin
    code = binary.read_bytes()
    if symbols.get('base') != 0 or symbols.get('slave_end') != len(code):
        raise SlaveError('the slave header is not at its start or the image has another length')
    return code, symbols


def position_independent(generated: Path, work: Path, **tools) -> tuple[bytes, dict[str, int]]:
    """The slave linked at 0 and at PROBE_ORIGIN must be identical: WHDLoad
    loads it anywhere and the hunk carries no relocations."""
    low, symbols = assemble(generated, work, 0, **tools)
    high, _ = assemble(generated, work, PROBE_ORIGIN, **tools)
    if low != high:
        offset = next(index for index, (a, b) in enumerate(zip(low, high)) if a != b)
        raise SlaveError(f'the slave is not position independent (difference at offset ${offset:X})')
    return low, symbols


def hunk_executable(code: bytes) -> bytes:
    """One code hunk without relocations, as WHDLoad loads a slave."""
    padded = code + bytes(-len(code) % 4)
    longs = len(padded) // 4
    return (struct.pack('>IIIIII', HUNK_HEADER, 0, 1, 0, 0, longs)
            + struct.pack('>II', HUNK_CODE, longs) + padded + struct.pack('>I', HUNK_END))


def hunk_code(executable: bytes) -> bytes:
    """The code of a single-hunk executable written by hunk_executable."""
    header = struct.unpack_from('>IIIIII', executable)
    if header[0] != HUNK_HEADER or header[2] != 1 or header[3] != 0 or header[4] != 0:
        raise SlaveError('not a single-hunk executable')
    kind, longs = struct.unpack_from('>II', executable, 24)
    if kind != HUNK_CODE or longs != header[5]:
        raise SlaveError('the hunk is not a code hunk')
    end = 32 + 4 * longs
    if executable[end:] != struct.pack('>I', HUNK_END):
        raise SlaveError('the hunk has relocations or other blocks')
    return executable[32:end]


def icon(slave_name: str = SLAVE_NAME) -> bytes:
    """A Workbench project icon whose default tool is WHDLoad."""
    rows = ICON_PICTURE.splitlines()
    width, height = len(rows[0]), len(rows)
    words = (width + 15) // 16
    planes = []
    for plane in (1, 2):
        data = bytearray()
        for row in rows:
            bits = 0
            for x in range(words * 16):
                colour = '.kwb'.index(row[x]) if x < width else 0
                bits = bits << 1 | (colour & plane != 0)
            data += bits.to_bytes(words * 2, 'big')
        planes.append(bytes(data))

    def string(text: str) -> bytes:
        data = text.encode('ascii') + b'\0'
        return struct.pack('>I', len(data)) + data

    no_position = 0x80000000
    disk_object = struct.pack(
        '>HH' 'IhhhhHHH' 'IIIIIHI' 'BB' 'IIIIIII',
        0xE310, 1,                                  # magic, version
        0, 0, 0, width, height + 1, 4, 3, 1,        # gadget: size, image, boolean
        1, 0, 0, 0, 0, 0, 0,                        # gadget render image only
        4, 0,                                       # WBPROJECT
        1, 1, no_position, no_position, 0, 0, 10240)
    image = struct.pack('>hhhhhIBBI', 0, 0, width, height, 2, 1, 3, 0, 0)
    tooltypes = [f'SLAVE={slave_name}'] + ICON_TOOLTYPES
    return (disk_object + image + b''.join(planes) + string('WHDLoad')
            + struct.pack('>I', (len(tooltypes) + 1) * 4) + b''.join(string(t) for t in tooltypes))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('generated', type=Path, help='directory with slave_gen.i and base_table.bin')
    parser.add_argument('-o', '--output', type=Path, required=True, help='the slave file to write')
    parser.add_argument('--vasm', default='vasmm68k_mot')
    parser.add_argument('--vlink', default='vlink')
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory() as work:
            code, _ = position_independent(args.generated, Path(work), vasm=args.vasm, vlink=args.vlink)
        args.output.write_bytes(hunk_executable(code))
    except (OSError, SlaveError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1
    print(f'{args.output}: {len(code)} bytes of code')
    return 0


if __name__ == '__main__':
    sys.exit(main())
