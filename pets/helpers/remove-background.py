"""Turns art on a plain white or light background into a transparent, square WebP for a pet.

    python pets/helpers/remove-background.py <in.jpg|png> <out.webp> [--keep-shadow] [--size 440] [--tolerance 18] [--min-light 190] [--pocket 3000]

The background is flood-filled from the image's edges, so light areas inside the outline (eyes,
highlights) are kept. Large enclosed light patches, such as floor showing between legs, are removed
too: any enclosed patch of at least --pocket pixels. Edge pixels blended with the background are made partly transparent and
cleaned of their white fringe. --keep-shadow keeps a light grey drop shadow, faint, instead of
removing it. The result is cropped to the art, squared and scaled to fit --size pixels.
Needs Pillow (pip install pillow).
"""
import argparse
from collections import deque

from PIL import Image


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('src')
    p.add_argument('out')
    p.add_argument('--keep-shadow', action='store_true', help='keep a light grey drop shadow, faint')
    p.add_argument('--size', type=int, default=440, help='longest side of the result, in pixels (default 440)')
    p.add_argument('--tolerance', type=int, default=18, help='how grey a pixel can be and still count as background')
    p.add_argument('--min-light', type=int, default=190, help='darkest grey still counted as background; lower it to remove a drop shadow')
    p.add_argument('--pocket', type=int, default=3000, help='smallest enclosed light patch to remove, in source pixels')
    a = p.parse_args()

    im = Image.open(a.src).convert('RGB')
    w, h = im.size
    px = im.load()

    def light_grey(x, y):
        r, g, b = px[x, y]
        return max(r, g, b) - min(r, g, b) <= a.tolerance and min(r, g, b) >= a.min_light

    # 1. Flood-fill light, grey pixels inward from every edge pixel.
    bg = bytearray(w * h)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if light_grey(x, y):
                bg[y * w + x] = 1
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if light_grey(x, y) and not bg[y * w + x]:
                bg[y * w + x] = 1
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not bg[ny * w + nx] and light_grey(nx, ny):
                bg[ny * w + nx] = 1
                queue.append((nx, ny))

    # 1b. Enclosed light patches: fill each one, and keep it as background only if it's big.
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            i = sy * w + sx
            if bg[i] or seen[i] or not light_grey(sx, sy):
                continue
            patch, queue = [i], deque([(sx, sy)])
            seen[i] = 1
            while queue:
                x, y = queue.popleft()
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    j = ny * w + nx
                    if 0 <= nx < w and 0 <= ny < h and not seen[j] and not bg[j] and light_grey(nx, ny):
                        seen[j] = 1
                        patch.append(j)
                        queue.append((nx, ny))
            if len(patch) >= a.pocket:
                for j in patch:
                    bg[j] = 1

    # 2. Alpha: background is clear (or a faint shadow); pixels touching it are softened and unmixed from white.
    out = Image.new('RGBA', (w, h))
    o = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if bg[y * w + x]:
                darkness = 255 - min(r, g, b)
                alpha = min(90, darkness * 3) if a.keep_shadow and darkness > 8 else 0
                o[x, y] = (0, 0, 0, alpha)
                continue
            edge = any(0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]
                       for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
            if edge:
                alpha = max(0.25, min(1.0, (255 - min(r, g, b)) / 120))
                unmix = lambda c: max(0, min(255, round((c - 255 * (1 - alpha)) / alpha)))
                o[x, y] = (unmix(r), unmix(g), unmix(b), round(alpha * 255))
            else:
                o[x, y] = (r, g, b, 255)

    # 3. Crop to the art, square it and scale it.
    l, t, r, b = out.getchannel('A').getbbox()
    side = max(r - l, b - t)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(out.crop((l, t, r, b)), ((side - (r - l)) // 2, (side - (b - t)) // 2))
    if side > a.size:
        square = square.resize((a.size, a.size), Image.LANCZOS)
    square.save(a.out, quality=90, method=6)
    print(f'Saved {a.out} ({square.width}x{square.height})')


if __name__ == '__main__':
    main()
