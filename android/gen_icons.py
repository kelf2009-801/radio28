"""Generate radio28 app icons (all mipmap densities) — dark bg, green PTT circle."""
import os
import struct
import zlib

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

BG = (10, 10, 15)        # #0A0A0F
GREEN = (0, 255, 140)    # #00FF8C
GREEN_DARK = (0, 180, 100)

def png_write(path, w, h, px):
    """Write RGB PNG without external deps."""
    def chunk(t, data):
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t + data))
    rows = []
    for y in range(h):
        rows.append(b"\x00" + bytes(px[y * w * 3:(y + 1) * w * 3]))
    raw = b"".join(rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)

def draw(size):
    """Simple icon: dark rounded square, neon green ring + mic dot in center."""
    px = bytearray(size * size * 3)
    cx, cy = size / 2, size / 2
    outer_r = size * 0.42
    ring_w = size * 0.06
    inner_r = outer_r - ring_w
    mic_r = size * 0.13
    # rounded rect mask params
    rr = size * 0.22  # corner radius

    def inside_rounded(x, y):
        # check if (x,y) inside rounded square
        ax = abs(x - cx) - (size / 2 - rr)
        ay = abs(y - cy) - (size / 2 - rr)
        if ax <= 0 or ay <= 0:
            return True
        return (ax * ax + ay * ay) <= rr * rr

    for y in range(size):
        for x in range(size):
            i = (y * size + x) * 3
            if not inside_rounded(x + 0.5, y + 0.5):
                # transparent-ish (we use dark for launcher bg)
                px[i:i + 3] = bytes(BG)
                continue
            # base bg
            px[i:i + 3] = bytes(BG)
            dx, dy = x - cx, y - cy
            d2 = dx * dx + dy * dy
            # ring
            if inner_r * inner_r <= d2 <= outer_r * outer_r:
                px[i:i + 3] = bytes(GREEN)
            # mic dot
            elif d2 <= mic_r * mic_r:
                px[i:i + 3] = bytes(GREEN_DARK)
    return px

out_base = r"D:\Hermes_Projects\radio28\android\app\src\main\res"
for dpi, sz in SIZES.items():
    d = os.path.join(out_base, f"mipmap-{dpi}")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "ic_launcher.png")
    png_write(p, sz, sz, draw(sz))
    print(f"{p} ({sz}x{sz})")
print("done")
