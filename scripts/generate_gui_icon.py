#!/usr/bin/env python3
"""Generate the ThermoTwin-F Windows icon without external dependencies."""

from __future__ import annotations

import math
import struct
import sys
from pathlib import Path


def clamp(x: float) -> int:
    return max(0, min(255, int(round(x))))


def blend(dst: tuple[int, int, int, int], src: tuple[int, int, int, int], a: float) -> tuple[int, int, int, int]:
    return tuple(clamp(dst[i] * (1.0 - a) + src[i] * a) for i in range(4))


def draw_icon(size: int) -> bytes:
    bg_top = (19, 31, 47, 255)
    bg_bottom = (8, 14, 26, 255)
    green = (82, 185, 124, 255)
    blue = (54, 138, 224, 255)
    amber = (242, 169, 59, 255)
    red = (220, 82, 63, 255)
    ink = (235, 243, 247, 255)
    grid = (54, 74, 95, 255)

    pixels = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]
    cx = (size - 1) / 2.0
    cy = (size - 1) / 2.0
    radius = size * 0.46

    for y in range(size):
        t = y / max(1, size - 1)
        base = blend(bg_top, bg_bottom, t)
        for x in range(size):
            dx = x - cx
            dy = y - cy
            d = math.hypot(dx, dy)
            if d <= radius:
                edge = 1.0
                if d > radius - 2.0:
                    edge = max(0.0, radius - d) / 2.0
                pixels[y][x] = blend((0, 0, 0, 0), base, edge)

    # Inner grid.
    for i in range(4, size - 4, max(4, size // 8)):
        for x in range(size):
            if pixels[i][x][3] > 0:
                pixels[i][x] = blend(pixels[i][x], grid, 0.35)
            if pixels[x][i][3] > 0:
                pixels[x][i] = blend(pixels[x][i], grid, 0.35)

    # Three supply bars.
    bars = [
        (0.26, 0.34, 0.78, 0.43, green),
        (0.26, 0.47, 0.64, 0.56, blue),
        (0.26, 0.60, 0.50, 0.69, amber),
    ]
    for x0, y0, x1, y1, color in bars:
        for y in range(int(size * y0), int(size * y1)):
            for x in range(int(size * x0), int(size * x1)):
                if 0 <= x < size and 0 <= y < size and pixels[y][x][3] > 0:
                    pixels[y][x] = color

    # Demand/load pulse.
    for y in range(int(size * 0.30), int(size * 0.74)):
        x = int(size * (0.72 + 0.07 * math.sin((y / size) * math.tau * 2.0)))
        for dx in range(-1, max(2, size // 28)):
            xx = x + dx
            if 0 <= xx < size and pixels[y][xx][3] > 0:
                pixels[y][xx] = red

    # Center node.
    node_r = max(3, size // 10)
    for y in range(size):
        for x in range(size):
            if math.hypot(x - cx, y - cy) <= node_r and pixels[y][x][3] > 0:
                pixels[y][x] = blend(pixels[y][x], ink, 0.82)

    return encode_dib_32(size, pixels)


def encode_dib_32(size: int, pixels: list[list[tuple[int, int, int, int]]]) -> bytes:
    header = struct.pack(
        "<IIIHHIIIIII",
        40,
        size,
        size * 2,
        1,
        32,
        0,
        size * size * 4,
        0,
        0,
        0,
        0,
    )
    xor = bytearray()
    for y in range(size - 1, -1, -1):
        for r, g, b, a in pixels[y]:
            xor.extend((b, g, r, a))
    mask_stride = ((size + 31) // 32) * 4
    mask = bytes(mask_stride * size)
    return header + bytes(xor) + mask


def write_ico(path: Path) -> None:
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = [draw_icon(size) for size in sizes]
    offset = 6 + 16 * len(sizes)
    entries = bytearray()
    for size, image in zip(sizes, images):
        dim = 0 if size == 256 else size
        entries.extend(struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(image), offset))
        offset += len(image)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack("<HHH", 0, 1, len(sizes)) + entries + b"".join(images))


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("gui/app_icon.ico")
    write_ico(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
