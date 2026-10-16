#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.91b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Decode RNC methods 1 and 2 using Python's standard library.

Input: bytes containing an RNC method-1 or method-2 header and packed payload.
Output: the unpacked bytes; both CRC-16 values and the declared sizes are
validated. The format lead was ScummVM common/compression/rnc_deco.cpp (GPL
source read as an algorithm reference); this implementation uses a separate bit
reservoir and canonical Huffman decoder, with no copied source. The CRC-16
values every stream carries give an independent check of the result. Method 2
is decoded separately from its control-prefix grammar. No compressor is
implemented. Both methods are tested against the packed files of the SWOS 96-97
disks.
"""
from __future__ import annotations

import struct


class RNCError(ValueError):
    """An invalid or unsupported RNC stream."""


def crc16(data: bytes) -> int:
    """CRC-16/ARC: reflected polynomial 0xA001, initial value zero."""
    result = 0
    for byte in data:
        result ^= byte
        for _ in range(8):
            result = (result >> 1) ^ (0xA001 if result & 1 else 0)
    return result


class _Stream:
    def __init__(self, data: bytes):
        self.data = data
        self.cursor = 0
        self.bits = 0
        self.count = 0

    def read(self, count: int) -> int:
        # Words are little-endian and consumed least-significant bit first.
        while self.count < count:
            if self.cursor >= len(self.data):
                raise RNCError("truncated control bits")
            word = int.from_bytes(self.data[self.cursor:self.cursor + 2], "little")
            self.cursor += 2
            self.bits |= word << self.count
            self.count += 16
        value = self.bits & ((1 << count) - 1)
        self.bits >>= count
        self.count -= count
        return value

    def literals(self, count: int) -> bytes:
        if not count:
            return b""
        end = self.cursor + count
        if end > len(self.data):
            raise RNCError("truncated literals")
        result = self.data[self.cursor:end]
        self.cursor = end
        return result

    def table(self) -> dict[tuple[int, int], int]:
        count = self.read(5)
        if count > 16:
            raise RNCError("Huffman alphabet exceeds 16 symbols")
        lengths = [self.read(4) for _ in range(count)]
        result = {}
        code = 0
        for length in range(1, 16):
            code <<= 1
            for symbol, size in enumerate(lengths):
                if size == length:
                    if code >= 1 << length:
                        raise RNCError("oversubscribed Huffman table")
                    result[length, code] = symbol
                    code += 1
        return result

    def value(self, table: dict[tuple[int, int], int]) -> int:
        code = 0
        for length in range(1, 16):
            code = (code << 1) | self.read(1)
            symbol = table.get((length, code))
            if symbol is not None:
                if symbol < 2:
                    return symbol
                return (1 << (symbol - 1)) | self.read(symbol - 1)
        raise RNCError("invalid Huffman code")


def _unpack1(data: bytes, *, max_output: int = 16 * 1024 * 1024) -> bytes:
    """Decode one RNC1 stream; permit unrelated trailing bytes after the stream."""
    if len(data) < 18 or data[:4] != b"RNC\x01":
        raise RNCError("expected an RNC method-1 stream")
    output_size, packed_size, output_crc, packed_crc, _leeway, blocks = struct.unpack_from(
        ">IIHHBB", data, 4
    )
    if output_size > max_output:
        raise RNCError("declared output exceeds configured limit")
    if packed_size > len(data) - 18:
        raise RNCError("truncated packed payload")
    payload = data[18:18 + packed_size]
    if crc16(payload) != packed_crc:
        raise RNCError("packed CRC mismatch")
    stream = _Stream(payload)
    if stream.read(2):
        raise RNCError("locked/encrypted RNC stream is unsupported")
    output = bytearray()
    for _ in range(blocks):
        literal_table, offset_table, length_table = [stream.table() for _ in range(3)]
        runs = stream.read(16)
        if not runs:
            raise RNCError("empty RNC block")
        for run in range(runs):
            literal_count = stream.value(literal_table)
            if len(output) + literal_count > output_size:
                raise RNCError("literal run exceeds output size")
            output.extend(stream.literals(literal_count))
            if run != runs - 1:
                distance = stream.value(offset_table) + 1
                length = stream.value(length_table) + 2
                if distance > len(output):
                    raise RNCError("back-reference precedes output")
                if len(output) + length > output_size:
                    raise RNCError("back-reference exceeds output size")
                for _ in range(length):
                    output.append(output[-distance])
    if len(output) != output_size:
        raise RNCError(f"output size mismatch: {len(output)} != {output_size}")
    if crc16(output) != output_crc:
        raise RNCError("unpacked CRC mismatch")
    return bytes(output)


class _M2Stream:
    """MSB-first control bytes interleaved with direct payload bytes."""

    def __init__(self, payload: bytes):
        self.payload = payload
        self.cursor = 0
        self.control = 0
        self.remaining = 0

    def byte(self) -> int:
        if self.cursor == len(self.payload):
            raise RNCError("truncated method-2 payload")
        value = self.payload[self.cursor]
        self.cursor += 1
        return value

    def bit(self) -> int:
        if not self.remaining:
            self.control = self.byte()
            self.remaining = 8
        self.remaining -= 1
        return (self.control >> self.remaining) & 1

    def bits(self, count: int) -> int:
        value = 0
        for _ in range(count):
            value = 2 * value + self.bit()
        return value

    def distance(self, short: bool) -> int:
        high = 0
        if not short and self.bit():
            first = self.bit()
            if not self.bit():
                high = 1 if first else 2 + self.bit()
            else:
                high = 4 + 2 * first + self.bit()
                if not self.bit():
                    high = 2 * high + self.bit()
        return 256 * high + self.byte() + 1


def _unpack2(payload: bytes, output_size: int) -> bytes:
    source = _M2Stream(payload)
    if source.bits(2):
        raise RNCError("locked/encrypted RNC stream is unsupported")
    output = bytearray()

    def literal(count: int) -> None:
        if len(output) + count > output_size:
            raise RNCError("literal run exceeds output size")
        output.extend(source.byte() for _ in range(count))

    while True:
        if not source.bit():
            literal(1)
            continue
        short = False
        if not source.bit():
            selector = source.bit()
            if not source.bit():
                length = 4 + selector
            else:
                length = 6 + 2 * selector + source.bit()
                if length == 9:
                    literal(4 * (source.bits(4) + 3))
                    continue
        elif not source.bit():
            length, short = 2, True
        elif not source.bit():
            length = 3
        else:
            length = source.byte()
            if not length:
                if source.bit():
                    continue
                break
            length += 8
        distance = source.distance(short)
        if distance > len(output):
            raise RNCError("back-reference precedes output")
        if len(output) + length > output_size:
            raise RNCError("back-reference exceeds output size")
        for _ in range(length):
            output.append(output[-distance])
    return bytes(output)


def unpack(data: bytes, *, max_output: int = 16 * 1024 * 1024) -> bytes:
    """Decode RNC1/RNC2, validating lengths and both CRCs; allow trailing bytes."""
    if len(data) < 18 or data[:3] != b"RNC" or data[3] not in (1, 2):
        raise RNCError("expected an RNC method-1 or method-2 stream")
    if data[3] == 1:
        return _unpack1(data, max_output=max_output)
    output_size, packed_size, output_crc, packed_crc = struct.unpack_from(">IIHH", data, 4)
    if output_size > max_output:
        raise RNCError("declared output exceeds configured limit")
    if packed_size > len(data) - 18:
        raise RNCError("truncated packed payload")
    payload = data[18:18 + packed_size]
    if crc16(payload) != packed_crc:
        raise RNCError("packed CRC mismatch")
    output = _unpack2(payload, output_size)
    if len(output) != output_size:
        raise RNCError(f"output size mismatch: {len(output)} != {output_size}")
    if crc16(output) != output_crc:
        raise RNCError("unpacked CRC mismatch")
    return output


def main() -> None:
    """Unpack one file; tools/adf_extract.py --unpacked unpacks a whole disk."""
    import argparse
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    # The packed input is never overwritten by its own unpacked bytes.
    output = args.output.resolve()
    if output == args.input.resolve():
        parser.error("input and output must be different paths")
    raw = unpack(args.input.read_bytes())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(raw)
    print(f"{args.input}: {len(raw)} bytes -> {output}")


if __name__ == "__main__":
    main()
