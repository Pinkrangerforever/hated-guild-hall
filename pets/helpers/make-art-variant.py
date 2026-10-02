"""Makes a recolored copy of existing pet art, so a new egg or monster can reuse art and still look different.

    python pets/helpers/make-art-variant.py <source-image> --sheet <out.png>
        Renders the source in 8 hue shifts, labeled, to pick from.
    python pets/helpers/make-art-variant.py <source-image> <out-image> [--hue 90] [--sat 1.2] [--bright 1.0] [--tint #4a8f3c --tint-strength 0.3]
        Writes one variant. Transparency is kept.

Example: python pets/helpers/make-art-variant.py pets/eggs/curious-egg/assets/idle.webp pets/eggs/gorilla-egg/assets/idle.webp --hue 200
Needs Pillow (pip install pillow).
"""
import argparse

from PIL import Image, ImageDraw, ImageEnhance

SHEET_HUES = [0, 45, 90, 135, 180, 225, 270, 315]


def variant(image, hue=0, sat=1.0, bright=1.0, tint=None, tint_strength=0.3):
    image = image.convert('RGBA')
    alpha = image.getchannel('A')
    rgb = image.convert('RGB')
    if hue % 360:
        h, s, v = rgb.convert('HSV').split()
        shift = round(hue % 360 * 255 / 360)
        h = h.point(lambda x: (x + shift) % 256)
        rgb = Image.merge('HSV', (h, s, v)).convert('RGB')
    if sat != 1.0:
        rgb = ImageEnhance.Color(rgb).enhance(sat)
    if bright != 1.0:
        rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    if tint:
        color = tuple(int(tint.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4))
        rgb = Image.blend(rgb, Image.new('RGB', rgb.size, color), tint_strength)
    out = rgb.convert('RGBA')
    out.putalpha(alpha)
    return out


def sheet(image, out, size=150):
    cells = []
    for hue in SHEET_HUES:
        cell = Image.new('RGBA', (size, size + 22), (36, 27, 16, 255))
        art = variant(image, hue=hue)
        art.thumbnail((size - 10, size - 10))
        cell.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
        ImageDraw.Draw(cell).text((8, size + 4), f'--hue {hue}', fill=(236, 224, 200, 255))
        cells.append(cell)
    grid = Image.new('RGBA', (size * 4, (size + 22) * 2), (36, 27, 16, 255))
    for i, cell in enumerate(cells):
        grid.paste(cell, ((i % 4) * size, (i // 4) * (size + 22)))
    grid.convert('RGB').save(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source')
    parser.add_argument('out', nargs='?')
    parser.add_argument('--sheet', help='write a sheet of hue options here instead of one variant')
    parser.add_argument('--hue', type=float, default=0, help='hue shift in degrees, 0-360')
    parser.add_argument('--sat', type=float, default=1.0, help='saturation factor, 1 = unchanged')
    parser.add_argument('--bright', type=float, default=1.0, help='brightness factor, 1 = unchanged')
    parser.add_argument('--tint', help='tint color, such as #4a8f3c')
    parser.add_argument('--tint-strength', type=float, default=0.3)
    args = parser.parse_args()

    image = Image.open(args.source)
    image.seek(0)
    if args.sheet:
        sheet(image, args.sheet)
        print(f'Wrote {args.sheet}')
    elif args.out:
        variant(image, args.hue, args.sat, args.bright, args.tint, args.tint_strength).save(args.out, quality=90, method=6)
        print(f'Wrote {args.out}')
    else:
        parser.error('give an output path, or --sheet')


if __name__ == '__main__':
    main()
