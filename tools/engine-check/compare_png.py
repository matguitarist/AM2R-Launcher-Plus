"""Compares two PNG screenshots pixel by pixel (8-bit RGB or RGBA, no interlacing, as the engine writes).

    python3 -I compare_png.py <actual.png> <reference.png>

Prints "same", or "differs: N of M pixels" and exits 1. Standard library only.
"""
import struct
import sys
import zlib


def read(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    pos, idat, width = 8, b"", 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6) or interlace:
                raise ValueError(f"{path}: unsupported PNG (depth {depth}, color {color}, interlace {interlace})")
            channels = 4 if color == 6 else 3
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * channels
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            up = previous[x]
            corner = previous[x - channels] if x >= channels else 0
            if kind == 1:
                line[x] = (line[x] + left) & 255
            elif kind == 2:
                line[x] = (line[x] + up) & 255
            elif kind == 3:
                line[x] = (line[x] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[x] = (line[x] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def main():
    actual, reference = read(sys.argv[1]), read(sys.argv[2])
    if actual[:2] != reference[:2]:
        print(f"differs: size {actual[0]}x{actual[1]} vs {reference[0]}x{reference[1]}")
        sys.exit(1)
    width, height, channels = actual[0], actual[1], actual[2]
    if channels != reference[2]:
        print("differs: channel count")
        sys.exit(1)
    different = 0
    for row_a, row_b in zip(actual[3], reference[3]):
        if row_a != row_b:
            different += sum(1 for x in range(0, len(row_a), channels) if row_a[x:x + channels] != row_b[x:x + channels])
    if different:
        print(f"differs: {different} of {width * height} pixels")
        sys.exit(1)
    print("same")


if __name__ == "__main__":
    main()
