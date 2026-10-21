"""Build the Hated Companion addon's card art and card data from the rendered cards.

    python tools/tcg_art/render_cards.py --plain        # first: the cards without their rarity glow (cards_plain/)
    python tools/tcg_art/make_addon_cards.py

Writes into addons/HatedCompanion/:
    Cards/c01.blp ...      the card art, 12 cards per 1024x1024 sheet (4 x 3, 248 x 340 each), DXT1-compressed BLP2
                           (WoW's own texture format; DXT1 = 4 bits a pixel, with on/off transparency)
    HatedTCGCards.lua      HatedTCG_CARDS[dbf] = { name, rarity 1-5, cost, attack, health, type, class, set, text, sheet, slot }
The addon draws the rarity glow itself, so the art has none.
"""
import json, os, re, struct, sys
import numpy as np
from PIL import Image

HOME = os.path.join(os.path.expanduser('~'), 'Documents', 'Hearthstone Art')
ADDON = os.path.join(os.path.dirname(__file__), '..', '..', 'addons', 'HatedCompanion')
SHEET, CW, CH, COLS, ROWS = 1024, 248, 340, 4, 3
MARGIN = 22                          # the rendered cards have a transparent border (where the site's glow goes)
RARITY = {'FREE': 1, 'COMMON': 2, 'RARE': 3, 'EPIC': 4, 'LEGENDARY': 5}
TYPE = {'MINION': 'M', 'SPELL': 'S', 'WEAPON': 'W', 'HERO': 'H', 'LOCATION': 'L'}


# ---------- DXT1 ----------
def dxt1(img):
    """RGBA uint8 (H, W, 4), H and W multiples of 4 -> DXT1 bytes (row-major 4x4 blocks)."""
    h, w = img.shape[:2]
    blk = img.reshape(h // 4, 4, w // 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 4)
    rgb, clear = blk[..., :3].astype(np.float32), blk[..., 3] < 128
    n = len(blk)
    solid = ~clear
    cnt = np.maximum(solid.sum(1, keepdims=True), 1)
    mean = (rgb * solid[..., None]).sum(1) / cnt
    d = (rgb - mean[:, None]) * solid[..., None]
    cov = np.einsum('nki,nkj->nij', d, d)
    axis = np.ones((n, 3), np.float32)
    for _ in range(6):                                       # principal colour axis of each block
        axis = np.einsum('nij,nj->ni', cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    t = np.einsum('nki,ni->nk', d, axis)
    big = np.where(solid, t, -1e9).max(1); small = np.where(solid, t, 1e9).min(1)
    big = np.where(big < -1e8, 0, big); small = np.where(small > 1e8, 0, small)
    inset = (big - small) / 16
    e0 = np.clip(mean + axis * (big - inset)[:, None], 0, 255); e1 = np.clip(mean + axis * (small + inset)[:, None], 0, 255)

    def to565(c):
        c = np.round(c).astype(np.int32)
        return ((c[:, 0] >> 3) << 11) | ((c[:, 1] >> 2) << 5) | (c[:, 2] >> 3)
    def from565(v):
        r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
        return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], 1).astype(np.float32)

    a0, a1 = to565(e0), to565(e1)
    has_clear = clear.any(1)
    # 4-colour blocks need c0 > c1; blocks with transparent pixels use the 3-colour mode (c0 <= c1, index 3 = clear)
    swap = np.where(has_clear, a0 > a1, a0 < a1)
    a0, a1 = np.where(swap, a1, a0), np.where(swap, a0, a1)
    c0, c1 = from565(a0), from565(a1)
    four = np.stack([c0, c1, (2 * c0 + c1) / 3, (c0 + 2 * c1) / 3], 1)
    three = np.stack([c0, c1, (c0 + c1) / 2, np.full_like(c0, 1e6)], 1)
    pal = np.where(has_clear[:, None, None], three, four)
    dist = ((rgb[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(-1)
    idx = np.where(clear, 3, idx)
    same = (a0 == a1) & ~has_clear                           # flat block: everything uses colour 0
    idx = np.where(same[:, None], 0, idx)
    bits = (idx.astype(np.uint32) << (2 * np.arange(16, dtype=np.uint32))).sum(1).astype(np.uint32)
    out = np.zeros(n, dtype=[('c0', '<u2'), ('c1', '<u2'), ('i', '<u4')])
    out['c0'], out['c1'], out['i'] = a0, a1, bits
    return out.tobytes()


def blp2_dxt1(img):
    data = dxt1(img)
    h, w = img.shape[:2]
    head = b'BLP2' + struct.pack('<I4BII', 1, 2, 1, 0, 0, w, h)          # type 1, DXT, 1-bit alpha, DXT1, no mipmaps
    offs = [1172] + [0] * 15; sizes = [len(data)] + [0] * 15
    return head + struct.pack('<16I', *offs) + struct.pack('<16I', *sizes) + b'\0' * 1024 + data


# ---------- card text for the tooltip / list views ----------
def plain_text(t):
    t = (t or '').replace('[x]', '').replace('\n', ' ')
    t = re.sub(r'[$#][a-z]?(\d+)', r'\1', t).replace('_', ' ')
    t = re.sub(r'(\d+)(\D{0,12}?)\|4\(([^,)]*),([^)]*)\)', lambda m: m.group(1) + m.group(2) + (m.group(3) if m.group(1) == '1' else m.group(4)), t)
    t = re.sub(r'\{\d+\}', 'X', t)
    t = re.sub(r'<b>(.*?)</b>', r'|cffffd36a\1|r', t)           # keywords in gold
    t = re.sub(r'<[^>]+>', '', t)
    return re.sub(r'\s+', ' ', t).strip()


def lua(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    cards = json.load(open(os.path.join(HOME, 'manifest.json'), encoding='utf-8'))
    raw = {c['id']: c for c in json.load(open(os.path.join(HOME, 'cards.json'), encoding='utf-8'))}
    cards = [c for c in cards if c.get('dbfId') and os.path.exists(os.path.join(HOME, 'cards_plain', c['id'] + '.png'))]
    cards.sort(key=lambda c: c['dbfId'])                     # fixed order: a card keeps its sheet + slot when cards are added
    os.makedirs(os.path.join(ADDON, 'Cards'), exist_ok=True)
    per = COLS * ROWS
    lines = ['-- Generated by tools/tcg_art/make_addon_cards.py - do not edit by hand.',
             '-- HatedTCG_CARDS[dbf] = { name, rarity 1-5 (Common..Legendary), cost, attack, health, type (M/S/W/H/L), class, set, text, sheet, slot }',
             'HatedTCG_CARDS = {']
    for s in range(0, len(cards), per):
        sheet = np.zeros((SHEET, SHEET, 4), np.uint8)
        for k, c in enumerate(cards[s:s + per]):
            im = Image.open(os.path.join(HOME, 'cards_plain', c['id'] + '.png')).convert('RGBA')
            im = im.crop((MARGIN, MARGIN, im.width - MARGIN, im.height - MARGIN)).resize((CW, CH), Image.LANCZOS)
            x, y = (k % COLS) * CW, (k // COLS) * CH
            sheet[y:y + CH, x:x + CW] = np.asarray(im)
            r = c.get('rarity') or ''
            rar = 3 if (c['type'] == 'HERO' and c['id'].startswith('HERO_') and c.get('cardClass') not in ('DEMONHUNTER', 'DEATHKNIGHT')) else \
                  4 if c['id'].startswith('HERO_') else RARITY.get(r, 1)
            hp = c.get('health') if c.get('health') is not None else c.get('durability')
            lines.append('  [%d]={%s,%d,%s,%s,%s,"%s","%s","%s",%s,%d,%d},' % (
                c['dbfId'], lua(c['name']), rar, c.get('cost') if c.get('cost') is not None else 'nil',
                c.get('attack') if c.get('attack') is not None else 'nil', hp if hp is not None else 'nil',
                TYPE.get(c['type'], '?'), c.get('cardClass') or '', c.get('set') or '', lua(plain_text(raw.get(c['id'], {}).get('text'))),
                s // per + 1, k))
        with open(os.path.join(ADDON, 'Cards', 'c%02d.blp' % (s // per + 1)), 'wb') as f:
            f.write(blp2_dxt1(sheet))
    lines.append('}')
    lines.append('HatedTCG_SHEET = { size = %d, w = %d, h = %d, cols = %d, sheets = %d }' % (SHEET, CW, CH, COLS, (len(cards) + per - 1) // per))
    with open(os.path.join(ADDON, 'HatedTCGCards.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    total = sum(os.path.getsize(os.path.join(ADDON, 'Cards', n)) for n in os.listdir(os.path.join(ADDON, 'Cards')))
    print(f'{len(cards)} cards -> {(len(cards) + per - 1) // per} sheets, {total / 1e6:.1f} MB; HatedTCGCards.lua written')


if __name__ == '__main__':
    if '--test' in sys.argv:                                  # round-trip one card through DXT1 and Pillow's BLP reader
        im = Image.open(sys.argv[2]).convert('RGBA').resize((248, 340)).crop((0, 0, 248, 340))
        a = np.zeros((344, 248, 4), np.uint8); a[:340] = np.asarray(im)
        open(sys.argv[3], 'wb').write(blp2_dxt1(a))
        back = np.asarray(Image.open(sys.argv[3]).convert('RGBA')).astype(float)
        diff = (back[..., :3] - a[..., :3].astype(float))[a[..., 3] > 127]
        print('PSNR %.1f dB' % (10 * np.log10(255 ** 2 / max((diff ** 2).mean(), 1e-9))))
    else:
        main()
