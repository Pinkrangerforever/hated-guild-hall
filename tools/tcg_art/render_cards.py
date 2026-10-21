"""Render Hated TCG cards: Hearthstone card data + art, in our frames.

    python tools/tcg_art/render_cards.py                 # every card in Documents\\Hearthstone Art\\cards.json
    python tools/tcg_art/render_cards.py --ids VAN_EX1_298 HERO_10
    python tools/tcg_art/render_cards.py --sheet          # also a contact sheet of everything (for review)

Frames come from tcg/frames_draft (our own art). Card art and data come from fetch_hearthstone_art.py. Output goes
next to the data (Documents\\Hearthstone Art\\cards\\<id>.png and .webp) plus manifest.json for the website - not into
the repo, since the card art is Blizzard's.

Rules for choosing a frame:
    MINION -> minion frame (tribe on the plate)    SPELL -> spell frame (spell school on the plate)
    WEAPON -> minion frame + durability badge      LOCATION -> location frame (uses on the left circle)
    HERO   -> Alliance / Horde / Neutral hero frame by class, hero power in the text box, 30 health
Rarity is the colour of the card's outer border (Hearthstone Free -> Common white, Common -> Uncommon green,
Rare blue, Epic purple, Legendary orange). Heroes come from packs too: Rare, except Illidan and the Lich King (Epic).
"""
import argparse, json, os, re
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
FRAMES = os.path.join(REPO, 'tcg', 'frames_draft')
CINZEL = os.path.join(HERE, 'fonts', 'Cinzel.ttf')
WINFONTS = 'C:/Windows/Fonts/'
DATA = os.path.join(os.path.expanduser('~'), 'Documents', 'Hearthstone Art')

RARITY = {
    'FREE': ('Common', (236, 236, 236)), 'COMMON': ('Uncommon', (52, 220, 72)), 'RARE': ('Rare', (40, 140, 255)),
    'EPIC': ('Epic', (178, 70, 255)), 'LEGENDARY': ('Legendary', (255, 150, 20)),
}
ALLIANCE = {'MAGE', 'PALADIN', 'PRIEST', 'DRUID'}
HORDE = {'WARRIOR', 'SHAMAN', 'HUNTER', 'WARLOCK', 'ROGUE'}

# positions on each frame (frame pixels); the art window is found from the frame's transparent hole
LAYOUT = {
    'minion':   dict(frame='minion_nogem', cost=(82, 76, 57), name=(150, 38, 545, 104), plate=(120, 452, 530, 492),
                     text=(85, 512, 515, 718), attack=(75, 735), health=(536, 726)),
    'spell':    dict(frame='spell', cost=(72, 74, 57), name=(140, 28, 515, 92), plate=(155, 448, 425, 492), text=(70, 512, 515, 720)),
    'location': dict(frame='location', cost=(70, 74, 57), name=(140, 28, 515, 92), plate=(150, 430, 520, 478),
                     text=(75, 500, 510, 720), loc_dur=(86, 458)),
    'alliance': dict(frame='alliance_hero', cost=(95, 90, 60), plate=(110, 462, 505, 512), text=(100, 560, 520, 735),
                     attack=(75, 752), health=(546, 745), hero=True),
    'horde':    dict(frame='horde_hero', cost=(90, 95, 60), plate=(100, 472, 545, 522), text=(110, 560, 520, 735),
                     attack=(80, 760), health=(542, 747), hero=True),
    'neutral':  dict(frame='neutral_hero', cost=(85, 75, 58), plate=(110, 458, 510, 508), text=(120, 548, 495, 715),
                     attack=(98, 728), health=(528, 724), hero=True),
}

_cache = {}
def load(name):
    if name not in _cache:
        _cache[name] = Image.open(os.path.join(FRAMES, name + '.png')).convert('RGBA')
    return _cache[name]

def window(frame_name):
    key = 'win:' + frame_name
    if key not in _cache:
        a = np.asarray(load(frame_name).split()[3]); h, w = a.shape
        inner = np.zeros_like(a, bool); inner[int(h * 0.08):int(h * 0.62), int(w * 0.1):int(w * 0.9)] = True
        ys, xs = np.nonzero((a < 10) & inner)
        _cache[key] = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    return _cache[key]

def font(kind, size):
    if kind == 'cinzel':
        f = ImageFont.truetype(CINZEL, size)
        try: f.set_variation_by_name('Bold')
        except Exception: pass
        return f
    return ImageFont.truetype(WINFONTS + kind, size)

def outlined(d, xy, text, f, fill=(255, 255, 255), stroke=(0, 0, 0), sw=5):
    # centre on the glyphs' actual ink (anchor 'mm' centres on the font's line box, so digits sit off-centre)
    l, t, r, b = d.textbbox((0, 0), text, font=f, stroke_width=sw, anchor='ls')
    d.text((xy[0] - (l + r) / 2, xy[1] - (t + b) / 2), text, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke, anchor='ls')

def fit(d, text, maxw, size, minsize=16):
    while size > minsize:
        f = font('cinzel', size)
        if d.textlength(text, font=f) <= maxw: return f
        size -= 2
    return font('cinzel', minsize)

def clean_text(raw):
    raw = raw or ''
    # Hearthstone's line breaks are real ("Taunt" on its own line); "[x]" just means the breaks were placed by hand
    raw = raw.replace('[x]', '').replace('\n', ' ¶ ')
    raw = re.sub(r'[$#][a-z]?(\d+)', r'\1', raw).replace('_', ' ')
    raw = re.sub(r'(\d+)(\D{0,12}?)\|4\(([^,)]*),([^)]*)\)', lambda m: m.group(1) + m.group(2) + (m.group(3) if m.group(1) == '1' else m.group(4)), raw)
    raw = re.sub(r'\{\d+\}', 'X', raw)
    return re.sub(r'\s+', ' ', raw).strip()

def rich_text(d, box, raw):
    x0, y0, x1, y1 = box
    tokens, prev_space = [], True                      # (word, bold, italic, glued to the previous word)
    for part in re.split(r'(<b>.*?</b>|<i>.*?</i>)', clean_text(raw)):
        if not part: continue
        b, i = part.startswith('<b>'), part.startswith('<i>')
        plain = re.sub(r'<[^>]+>', '', part)
        for k, w in enumerate(plain.split()):
            # "Charge." - punctuation right after a bold keyword sits against it, no space
            glue = k == 0 and tokens and not plain[:1].isspace() and not prev_space
            tokens.append((w, b, i, bool(glue)))
        prev_space = plain[-1:].isspace() or not plain.strip()
    if not tokens: return
    for size in range(34, 13, -2):
        reg, bol, ita = font('georgia.ttf', size), font('georgiab.ttf', size), font('georgiai.ttf', size)
        sp = d.textlength(' ', font=reg); lines, line, lw = [], [], 0
        for w, b, i, g in tokens:
            if w == '¶':                                 # forced line break
                if line: lines.append((line, lw)); line, lw = [], 0
                continue
            f = bol if b else ita if i else reg; ww = d.textlength(w, font=f)
            gap = 0 if (g or not line) else sp
            if line and not g and lw + gap + ww > (x1 - x0):
                lines.append((line, lw)); line, lw, gap = [], 0, 0
            line.append((w, f, ww, gap)); lw += gap + ww
        if line: lines.append((line, lw))
        lh = size * 1.25
        if len(lines) * lh <= (y1 - y0): break
    y = y0 + ((y1 - y0) - len(lines) * lh) / 2
    for line, lw in lines:
        x = x0 + ((x1 - x0) - lw) / 2
        for w, f, ww, gap in line:
            x += gap
            d.text((x, y), w, font=f, fill=(40, 26, 12)); x += ww
        y += lh

def rarity_border(card, color, width=11, keep_out=()):
    """Tint the card's outer edge. keep_out: (x, y, r) circles - the mana orb, attack swords, health shield - left untinted."""
    a = np.asarray(card.split()[3])
    inner = cv2.erode((a > 128).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=width)
    rim = ((a > 128) & (inner == 0)).astype(np.uint8)
    for x, y, r in keep_out:
        cv2.circle(rim, (int(x), int(y)), int(r), 0, -1)
    # only the card body's edge: anything sticking out past the body (orb, swords, shield, hero ornaments) stays untinted
    op = a > 128; h, w = op.shape
    rows = op[int(h * 0.3):int(h * 0.7)]; cols = op[:, int(w * 0.3):int(w * 0.7)]
    l = int(np.median(rows.argmax(axis=1))); r = w - int(np.median(rows[:, ::-1].argmax(axis=1)))
    t = int(np.median(cols.argmax(axis=0))); b = h - int(np.median(cols[::-1].argmax(axis=0)))
    body = np.zeros_like(rim); body[t - 1:b + 1, l - 1:r + 1] = 1
    rim = (rim & body) > 0
    rgb = np.asarray(card.convert('RGB')).astype(np.float32)
    lum = rgb.mean(axis=2, keepdims=True) / 255.0
    tint = np.clip(np.array(color, np.float32) * (0.35 + lum * 1.25), 0, 255)
    soft = cv2.GaussianBlur(rim.astype(np.float32), (5, 5), 0)[..., None]
    out = rgb * (1 - soft) + tint * soft
    return Image.fromarray(np.dstack([out.astype(np.uint8), a]), 'RGBA')

def glow(card, color, strength):
    """Rarity colour drawn only BEHIND the card: a crisp halo a few pixels past the silhouette, then a soft fade."""
    P = 30
    a = np.zeros((card.height + 2 * P, card.width + 2 * P), np.uint8)
    a[P:P + card.height, P:P + card.width] = np.asarray(card.split()[3])
    edge = cv2.GaussianBlur(cv2.dilate(a, np.ones((9, 9), np.uint8)), (5, 5), 0).astype(np.float32)   # ~4px solid rim
    soft = cv2.GaussianBlur(a, (0, 0), 12).astype(np.float32) * 1.6 * strength                        # outer glow
    alpha = np.clip(np.maximum(edge, soft), 0, 255).astype(np.uint8)
    out = Image.new('RGBA', (card.width + 2 * P, card.height + 2 * P), color + (255,)); out.putalpha(Image.fromarray(alpha))
    out.alpha_composite(card, (P, P))
    return out

def rarity_of(card):
    """Hearthstone rarity code, with heroes re-rated: every card is pulled from packs, heroes included."""
    if card['id'].startswith('HERO_'):                 # the base heroes; hero cards (AV_...) keep their own rarity
        return 'EPIC' if card.get('cardClass') in ('DEMONHUNTER', 'DEATHKNIGHT') else 'RARE'
    return card.get('rarity')

def kind_of(card):
    t = card.get('type')
    if t == 'HERO':
        c = card.get('cardClass')
        return 'alliance' if c in ALLIANCE else 'horde' if c in HORDE else 'neutral'
    return {'MINION': 'minion', 'SPELL': 'spell', 'WEAPON': 'minion', 'LOCATION': 'location'}.get(t)

def plate_of(card):
    t = card.get('type')
    if t == 'MINION':
        r = card.get('race') or ' '.join(card.get('races', []))
        return r.replace('ALL', 'All').title() if r else ''
    if t == 'SPELL': return (card.get('spellSchool') or '').replace('_', ' ').title()
    if t == 'WEAPON': return 'Weapon'
    if t == 'LOCATION': return 'Location'
    return ''

PLAIN_DIR = None

def render(card, art_path, by_dbf):
    kind = kind_of(card)
    L = LAYOUT[kind]
    frame = load(L['frame']); W, H = frame.size
    x0, y0, x1, y1 = window(L['frame'])
    # art: the centre of the picture (Hearthstone art has ragged, padded edges), a little larger than the hole
    pad = 10; ww, wh = x1 - x0 + pad * 2, y1 - y0 + pad * 2
    art = Image.open(art_path).convert('RGB'); s = art.width
    inner = art.crop((int(s * 0.12), int(s * 0.12), int(s * 0.88), int(s * 0.88)))
    r = max(ww / inner.width, wh / inner.height)
    inner = inner.resize((int(inner.width * r) + 1, int(inner.height * r) + 1), Image.LANCZOS)
    cx, cy = (inner.width - ww) // 2, (inner.height - wh) // 2
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    img.paste(inner.crop((cx, cy, cx + ww, cy + wh)), (x0 - pad, y0 - pad))
    img.alpha_composite(frame)
    is_weapon = card.get('type') == 'WEAPON'
    if is_weapon:
        hx, hy = L['health']
        hb = load('badge_durability').resize((112, 112), Image.LANCZOS)
        img.alpha_composite(hb, (int(hx - 56), int(hy - 56)))
    d = ImageDraw.Draw(img)
    if not card['id'].startswith('HERO_') and card.get('cost') is not None:
        cx_, cy_, rr = L['cost']
        orb = load('badge_mana').resize((rr * 2, rr * 2), Image.LANCZOS)
        img.alpha_composite(orb, (cx_ - rr, cy_ - rr))
        outlined(d, (cx_, cy_), str(card['cost']), font('georgiab.ttf', int(rr * 1.15)))
    name = card['name']
    if L.get('hero'):
        px0, py0, px1, py1 = L['plate']
        outlined(d, ((px0 + px1) / 2, (py0 + py1) / 2), name, fit(d, name, px1 - px0 - 30, 42), fill=(255, 255, 255), stroke=(15, 10, 6), sw=4)
        hp = by_dbf.get(card.get('heroPowerDbfId'))
        hp_text = re.sub(r'<b>\s*Hero Power\s*</b>', '', hp.get('text') or '') if hp else ''
        text = f"<b>Hero Power - {hp['name']}:</b> {re.sub(r'<[^>]+>', '', hp_text).strip()}" if hp else ''
        if not card['id'].startswith('HERO_') and card.get('text'):      # hero cards: their own text, then the new hero power
            text = card['text'] + ' ' + text
    else:
        nx0, ny0, nx1, ny1 = L['name']
        outlined(d, ((nx0 + nx1) / 2, (ny0 + ny1) / 2), name, fit(d, name, nx1 - nx0 - 24, 38), fill=(52, 30, 12), stroke=(236, 210, 160), sw=1)
        plate = plate_of(card)
        if plate:
            px0, py0, px1, py1 = L['plate']
            outlined(d, ((px0 + px1) / 2, (py0 + py1) / 2), plate, fit(d, plate, px1 - px0 - 24, 26), fill=(250, 240, 220), stroke=(20, 14, 8), sw=3)
        text = card.get('text', '')
    rich_text(d, L['text'], text)
    big = font('georgiab.ttf', 60)
    if 'attack' in L and card.get('attack') and not L.get('hero'):
        outlined(d, L['attack'], str(card['attack']), big)
    if 'health' in L:
        val = (30 if card['id'].startswith('HERO_') else card.get('armor')) if L.get('hero') else ((card.get('durability') or card.get('health')) if is_weapon else card.get('health'))
        if val is not None: outlined(d, (L['health'][0], L['health'][1] - 2), str(val), big)
    if L.get('loc_dur') and card.get('health') is not None:
        outlined(d, L['loc_dur'], str(card['health']), font('georgiab.ttf', 54))
    rated = rarity_of(card) in RARITY
    if rated:
        color = RARITY[rarity_of(card)][1]
        keep = [(*L[k], 64) for k in ('attack', 'health', 'loc_dur') if k in L]    # the sword disc / shield sitting on the edge
        if 'attack' in L and not L.get('hero'):                                    # and the two lower sword blades
            ax, ay = L['attack']; keep += [(ax - 48, ay + 46, 20), (ax + 50, ay + 47, 20)]
    if PLAIN_DIR:                                    # the WoW addon draws its own glow: keep a copy without it
        img.save(os.path.join(PLAIN_DIR, card['id'] + '.png'))
    if rated:
        img = glow(img, color, 1.0 if rarity_of(card) in ('EPIC', 'LEGENDARY') else 0.55)
    return img

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data', default=DATA)
    ap.add_argument('--ids', nargs='*')
    ap.add_argument('--sheet', action='store_true')
    ap.add_argument('--plain', action='store_true', help='also save each card without its rarity glow to cards_plain/ (for the WoW addon)')
    args = ap.parse_args()
    cards = json.load(open(os.path.join(args.data, 'cards.json'), encoding='utf-8'))
    by_dbf = {c.get('dbfId'): c for c in cards}
    todo = [c for c in cards if kind_of(c) and (not args.ids or c['id'] in args.ids)]
    out_dir = os.path.join(args.data, 'cards'); os.makedirs(out_dir, exist_ok=True)
    global PLAIN_DIR
    if args.plain:
        PLAIN_DIR = os.path.join(args.data, 'cards_plain'); os.makedirs(PLAIN_DIR, exist_ok=True)
    manifest, rendered = [], []
    for c in todo:
        art = os.path.join(args.data, 'art', c['id'] + '.jpg')
        if not os.path.exists(art):
            print('no art:', c['id'], c['name']); continue
        img = render(c, art, by_dbf)
        img.save(os.path.join(out_dir, c['id'] + '.png'))
        img.save(os.path.join(out_dir, c['id'] + '.webp'), quality=88, method=6)
        rendered.append((c, img))
        manifest.append({k: c.get(k) for k in ('id', 'dbfId', 'name', 'type', 'cardClass', 'set', 'rarity', 'cost', 'attack', 'health', 'durability', 'race', 'spellSchool', 'mechanics')}
                        | {'text': clean_text(c.get('text')), 'frame': kind_of(c), 'rarity': rarity_of(c), 'ourRarity': RARITY.get(rarity_of(c), ('', None))[0], 'image': c['id'] + '.webp'})
    if not args.ids:
        json.dump(manifest, open(os.path.join(args.data, 'manifest.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'rendered {len(rendered)} cards to {out_dir}')
    if args.sheet and rendered:
        tw, th, cols = 200, 270, 12
        rows = (len(rendered) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * tw, rows * th), (22, 18, 14))
        for i, (c, img) in enumerate(rendered):
            t = img.copy(); t.thumbnail((tw - 6, th - 6))
            sheet.paste(t, ((i % cols) * tw + (tw - t.width) // 2, (i // cols) * th + (th - t.height) // 2), t)
        sheet.save(os.path.join(args.data, 'contact_sheet.jpg'), quality=85)
        print('contact sheet:', os.path.join(args.data, 'contact_sheet.jpg'))

if __name__ == '__main__':
    main()
