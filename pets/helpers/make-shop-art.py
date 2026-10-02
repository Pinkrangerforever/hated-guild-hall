"""Builds an egg's Shop card banner from its idle art.

    python pets/helpers/make-shop-art.py <egg-key> [--bg <image>] [--art <image>]

Writes pets/eggs/<egg-key>/assets/shop.webp (480x160) and sets "shop_image" in egg.json.
The Shop shows the banner 80px tall and 150-260px wide, cropped to fill, so the egg sits
in the middle third, where it survives the narrowest card. Needs Pillow (pip install pillow).
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PETS = Path(__file__).resolve().parent.parent
WIDTH, HEIGHT = 480, 160
EGG_HEIGHT = 136
# Site palette (index.html :root): --bg-card, --bg-tertiary, --yellow
CENTER, EDGE, GOLD = (0x49, 0x3A, 0x24), (0x1C, 0x14, 0x0B), (0xCF, 0x9A, 0x44)


def radial_background():
    """Warm radial gradient, lightest behind the egg."""
    bg = Image.new('RGB', (WIDTH, HEIGHT), EDGE)
    mask = Image.new('L', (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(mask).ellipse((WIDTH * 0.2, -HEIGHT * 0.4, WIDTH * 0.8, HEIGHT * 1.4), fill=255)
    bg.paste(Image.new('RGB', (WIDTH, HEIGHT), CENTER), mask=mask.filter(ImageFilter.GaussianBlur(60)))
    return bg


def cover(image):
    """Scale and crop a custom background to fill the banner."""
    scale = max(WIDTH / image.width, HEIGHT / image.height)
    image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left, top = (image.width - WIDTH) // 2, (image.height - HEIGHT) // 2
    return image.crop((left, top, left + WIDTH, top + HEIGHT)).convert('RGB')


def first_frame(path, anim):
    """The still to use: a GIF's first frame, or a sprite strip's first frame."""
    image = Image.open(path)
    image.seek(0)
    image = image.convert('RGBA')
    if (anim or {}).get('frames', 1) > 1:
        image = image.crop((0, 0, anim['frame_width'], anim['frame_height']))
    return image.crop(image.getchannel('A').getbbox())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('egg')
    parser.add_argument('--bg', help='custom background image, cropped to fill')
    parser.add_argument('--art', help='image to show instead of the egg idle art')
    args = parser.parse_args()

    folder = PETS / 'eggs' / args.egg
    egg_file = folder / 'egg.json'
    egg = json.loads(egg_file.read_text(encoding='utf-8'))
    idle = egg['animations']['idle']
    art = first_frame(Path(args.art) if args.art else folder / idle['src'], None if args.art else idle)
    art = art.resize((round(art.width * EGG_HEIGHT / art.height), EGG_HEIGHT), Image.LANCZOS)

    banner = cover(Image.open(args.bg)) if args.bg else radial_background()
    banner = banner.convert('RGBA')

    # Soft gold glow behind the egg, then a contact shadow under it.
    glow = Image.new('RGBA', banner.size, (0, 0, 0, 0))
    cx, cy = WIDTH // 2, HEIGHT // 2
    ImageDraw.Draw(glow).ellipse((cx - 70, cy - 70, cx + 70, cy + 70), fill=GOLD + (90,))
    banner.alpha_composite(glow.filter(ImageFilter.GaussianBlur(28)))
    shadow = Image.new('RGBA', banner.size, (0, 0, 0, 0))
    floor = (HEIGHT + EGG_HEIGHT) // 2
    ImageDraw.Draw(shadow).ellipse((cx - art.width * 0.45, floor - 9, cx + art.width * 0.45, floor + 3), fill=(0, 0, 0, 150))
    banner.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4)))
    banner.alpha_composite(art, (cx - art.width // 2, (HEIGHT - EGG_HEIGHT) // 2))

    out = folder / 'assets' / 'shop.webp'
    banner.convert('RGB').save(out, quality=88, method=6)
    egg['shop_image'] = 'assets/shop.webp'
    egg.pop('icon', None)
    egg_file.write_text(json.dumps(egg, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'Wrote {out.relative_to(PETS.parent).as_posix()} ({out.stat().st_size // 1024} KB) and set "shop_image" in egg.json')


if __name__ == '__main__':
    main()
