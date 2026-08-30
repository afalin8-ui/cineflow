#!/usr/bin/env python3
# Значок программы. Рисуем сами, без внешних библиотек: сборка не должна
# зависеть от того, что установлено на машине.
import struct, math

BG     = (0x24, 0x23, 0x22)   # тёмная плашка
BORDER = (0x4a, 0x47, 0x41)
KEY    = (0xd9, 0x77, 0x57)   # терракотовые кнопки
KEY2   = (0xc9, 0xc5, 0xbb)   # верхняя — светлая, как «активная»

def rr(px, py, x, y, w, h, r):
    """расстояние до скруглённого прямоугольника < 0 внутри"""
    cx = min(max(px, x + r), x + w - r)
    cy = min(max(py, y + r), y + h - r)
    return math.hypot(px - cx, py - cy) - r

def render(n):
    ss = 4                                   # сглаживание простым усреднением
    buf = [[(0, 0, 0, 0)] * n for _ in range(n)]
    for iy in range(n):
        for ix in range(n):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    px = ix + (sx + 0.5) / ss
                    py = iy + (sy + 0.5) / ss
                    col = (0, 0, 0, 0)
                    # плашка
                    if rr(px, py, n * 0.06, n * 0.06, n * 0.88, n * 0.88, n * 0.20) < 0:
                        col = (*BG, 255)
                        if rr(px, py, n * 0.06, n * 0.06, n * 0.88, n * 0.88, n * 0.20) > -max(1.0, n * 0.035):
                            col = (*BORDER, 255)
                    # три кнопки полоской
                    bw, bh = n * 0.30, n * 0.185
                    bx = n * 0.20
                    for i, c in enumerate((KEY2, KEY, KEY)):
                        by = n * 0.175 + i * (bh + n * 0.075)
                        if rr(px, py, bx, by, bw, bh, n * 0.055) < 0:
                            col = (*c, 255)
                    # правая половина — «экран», чуть светлее плашки
                    for i in range(3):
                        by = n * 0.175 + i * (bh + n * 0.075)
                        if rr(px, py, n * 0.56, by, n * 0.24, bh, n * 0.05) < 0:
                            col = (0x33, 0x31, 0x2d, 255)
                    for k in range(4):
                        acc[k] += col[k]
            buf[iy][ix] = tuple(int(v / (ss * ss)) for v in acc)
    return buf

def dib(buf, n):
    hdr = struct.pack('<IiiHHIIiiII', 40, n, n * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    px = bytearray()
    for iy in range(n - 1, -1, -1):          # снизу вверх
        for ix in range(n):
            r, g, b, a = buf[iy][ix]
            px += bytes((b, g, r, a))
    stride = ((n + 31) // 32) * 4
    mask = bytes(stride * n)
    return hdr + bytes(px) + mask

sizes = [16, 24, 32, 48, 64]
imgs = [dib(render(n), n) for n in sizes]
out = struct.pack('<HHH', 0, 1, len(sizes))
off = 6 + 16 * len(sizes)
for n, img in zip(sizes, imgs):
    out += struct.pack('<BBBBHHII', n & 0xFF, n & 0xFF, 0, 0, 1, 32, len(img), off)
    off += len(img)
for img in imgs:
    out += img
open('penbar.ico', 'wb').write(out)
print('penbar.ico', len(out), 'байт')
