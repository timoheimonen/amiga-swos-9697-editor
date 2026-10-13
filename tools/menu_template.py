#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Decode a compact menu template of the Amiga SWOS2 into a JSON model.

Input: a raw relocated executable and a template address (default image base
$180000). Output: JSON including source offsets, geometry and callback pointers.
This reads templates, not the expanded $38-byte runtime entry arrays.
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path


def decode(image: bytes, address: int, image_base: int = 0x180000) -> dict:
    cursor = address - image_base

    def read(count: int) -> bytes:
        nonlocal cursor
        if cursor < 0 or cursor + count > len(image):
            raise ValueError("truncated or out-of-range menu template")
        value = image[cursor:cursor + count]
        cursor += count
        return value

    def word() -> int:
        return int.from_bytes(read(2), "big")

    def longword() -> int:
        return int.from_bytes(read(4), "big")

    def peek() -> int:
        if not 0 <= cursor <= len(image) - 2:
            raise ValueError("missing menu terminator")
        return int.from_bytes(image[cursor:cursor + 2], "big")

    def signed(value: int) -> int:
        return value - 65536 if value & 32768 else value

    def defaults() -> dict:
        return {"hidden": 0, "disabled": 0, "navigation": [255] * 4,
                "navigation_source": None, "navigation_fallback": [255] * 4,
                "navigation_redirect": [255] * 4,
                "background_kind": 0, "background_value": 0,
                "content_kind": 0, "content_style": 0, "content_value": 0,
                "action": 0, "action_source": None, "event_mask": 0, "pre_draw": 0, "post_draw": 0}

    header = [longword() for _ in range(4)]
    entries, shift, byte_geometry = [], [0, 0], False
    inherited = defaults()
    while True:
        tag = peek()
        if tag == 0xFC19:
            word()
            break
        if tag == 0xFC1A:
            word()
            shift = [signed(word()), signed(word())]
            continue
        if tag == 0xFC1C:
            word()
            inherited = defaults()
            continue
        is_default = tag == 0xFC1B
        source = cursor
        if is_default:
            word()
        if peek() in (0xFFFF, 0xFFFE):
            byte_geometry = word() == 0xFFFF
        geometry = list(read(4)) if byte_geometry else [signed(word()) for _ in range(4)]
        entry = copy.deepcopy(inherited)
        entry.update(source_start=source, geometry=[geometry[0] + 24 + shift[0],
                     geometry[1] + 36 + shift[1], geometry[2], geometry[3]])
        while (opcode := word()) != 0:
            if opcode == 1:
                entry["hidden"] = 1
            elif opcode == 2:
                entry["navigation_source"] = cursor
                entry["navigation"] = list(read(4))
            elif 3 <= opcode <= 6:
                entry["background_kind"] = opcode - 2
                entry["background_value"] = longword() if opcode == 3 else word()
            elif opcode in (7, 8, 9, 10, 11, 12, 21, 22):
                kinds = {7: 1, 8: 2, 9: 3, 10: 4, 11: 5, 12: 6, 21: 7, 22: 2}
                entry["content_kind"] = kinds[opcode]
                entry["content_style"] = word() if opcode in (8, 10, 11, 12, 22) else 0
                entry["content_value"] = (0xFFFFFFFF if opcode == 22 else
                                          word() if opcode in (9, 12) else longword())
                if opcode == 8 and 0 < entry["content_value"] < 256:
                    entry["content_value"] = 0xFFFFFFFF
            elif opcode in (13, 14):
                entry["event_mask"] = 0x20 if opcode == 13 else word()
                entry["action_source"] = cursor
                entry["action"] = longword()
            elif opcode in (15, 16):
                entry["pre_draw" if opcode == 15 else "post_draw"] = longword()
            elif 17 <= opcode <= 20:
                redirect, fallback = read(2)
                entry["navigation_redirect"][opcode - 17] = redirect
                entry["navigation_fallback"][opcode - 17] = fallback
            else:
                raise ValueError(f"unknown menu opcode {opcode} at ${image_base + cursor - 2:X}")
        entry["source_end"] = cursor
        if is_default:
            inherited = entry
        else:
            pointer = entry["content_value"] - image_base
            if entry["content_kind"] == 2 and 0 <= pointer < len(image):
                end = image.find(b"\0", pointer)
                if end < 0:
                    raise ValueError("unterminated menu text")
                entry["text"] = image[pointer:end].decode("latin1")
            entries.append(entry)
        if len(entries) > 114:
            raise ValueError("menu exceeds the game's maximum entry capacity")
    text_buffers = sum(e["content_kind"] == 2 and e["content_value"] == 0xFFFFFFFF
                       for e in entries)
    used = 22 + 56 * len(entries) + 70 * text_buffers
    if not entries or used > 6500:
        raise ValueError("empty menu or expanded arena overflow")
    return {"address": address, "source_end": cursor, "source_size": cursor - (address - image_base),
            "init": header[0], "restore": header[1], "draw": header[2],
            "selected": header[3], "expanded_size": used, "entries": entries}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("address", type=lambda s: int(s, 0))
    parser.add_argument("--image-base", type=lambda s: int(s, 0), default=0x180000)
    args = parser.parse_args()
    print(json.dumps(decode(args.image.read_bytes(), args.address, args.image_base), indent=2))


if __name__ == "__main__":
    main()
