"""Fetch Hearthstone's card data and frameless card art from HearthstoneJSON (https://hearthstonejson.com).

The card art belongs to Blizzard Entertainment. HearthstoneJSON asks that images be re-hosted rather than linked
directly, which is what this does. For the guild's own non-commercial use; nothing is written into the repo.

    python tools/tcg_art/fetch_hearthstone_art.py              # the Classic set (382 cards), 512x512 JPG
    python tools/tcg_art/fetch_hearthstone_art.py --sets ALL   # every collectible card (8,000+)
    python tools/tcg_art/fetch_hearthstone_art.py --sets VANILLA NAXX GVG   # chosen sets (HearthstoneJSON set codes)
    python tools/tcg_art/fetch_hearthstone_art.py --sets VANILLA NAXX --ids OG_280 TRL_541   # sets plus single cards
    python tools/tcg_art/fetch_hearthstone_art.py --orig       # original-resolution PNGs instead (much bigger)
    python tools/tcg_art/fetch_hearthstone_art.py --data-only  # just the card spreadsheet

Also fetched: the hero power of every collectible hero, and the base class heroes (Garrosh, Jaina, Thrall...).

Output (default Documents\\Hearthstone Art):
    art/<card id>.jpg      the artwork, no frame
    cards.csv              id, name, type, class, set, rarity, cost, attack, health, durability, text, artist, ...
    cards.json             the raw HearthstoneJSON data for those cards

Safe to stop and re-run: art already downloaded is skipped.
"""
import argparse, csv, json, os, re, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

API = 'https://api.hearthstonejson.com/v1/latest/enUS/cards.json'
ART = 'https://art.hearthstonejson.com/v1/{size}/{id}.{ext}'
UA = {'User-Agent': 'Mozilla/5.0 (HatedGuild card-art fetcher)'}


def get(url, timeout=90):
    for attempt in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 + attempt * 3)


def clean(text):
    """Card text without Hearthstone's markup (<b>, [x], $ for spell damage, # for healing)."""
    t = re.sub(r'<[^>]+>', '', text or '').replace('[x]', '').replace('\n', ' ')
    return re.sub(r'[$#](\d+)', r'\1', t).replace('_', ' ').strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=os.path.join(os.path.expanduser('~'), 'Documents', 'Hearthstone Art'))
    ap.add_argument('--sets', nargs='*', default=['VANILLA'], help='set codes (VANILLA = Classic), or ALL')
    ap.add_argument('--ids', nargs='*', default=[], help='single cards to add on top of the sets (card ids)')
    ap.add_argument('--orig', action='store_true', help='original-resolution PNGs instead of 512x512 JPGs')
    ap.add_argument('--data-only', action='store_true')
    ap.add_argument('--workers', type=int, default=6)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    print('reading the card list ...')
    cards = json.loads(get(API))
    by_dbf = {c.get('dbfId'): c for c in cards}
    want = None if [s.upper() for s in args.sets] == ['ALL'] else {s.upper() for s in args.sets}
    keep = [c for c in cards if c.get('collectible') and (want is None or c.get('set') in want or c['id'] in args.ids)]
    ids = {c['id'] for c in keep}
    # each collectible hero's hero power, and the base class heroes (HERO_01 Garrosh ... HERO_10 Illidan)
    extra = []
    for c in keep:
        hp = by_dbf.get(c.get('heroPowerDbfId'))
        if c.get('type') == 'HERO' and hp and hp['id'] not in ids:
            extra.append(hp); ids.add(hp['id'])
    for c in cards:
        if re.fullmatch(r'HERO_\d\d', c.get('id', '')) and c['id'] not in ids:
            extra.append(c); ids.add(c['id'])
            hp = by_dbf.get(c.get('heroPowerDbfId'))
            if hp and hp['id'] not in ids:
                extra.append(hp); ids.add(hp['id'])
    keep += extra
    print(f'{len(keep)} cards ({len(keep) - len(extra)} collectible from {"all sets" if want is None else ", ".join(sorted(want))} + {len(extra)} heroes / hero powers)')

    with open(os.path.join(args.out, 'cards.json'), 'w', encoding='utf-8') as f:
        json.dump(keep, f, ensure_ascii=False, indent=1)
    cols = ['id', 'dbfId', 'name', 'type', 'cardClass', 'set', 'rarity', 'cost', 'attack', 'health', 'durability', 'armor',
            'race', 'spellSchool', 'mechanics', 'text', 'flavor', 'artist', 'collectible']
    with open(os.path.join(args.out, 'cards.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for c in sorted(keep, key=lambda c: (c.get('set', ''), c.get('name', ''))):
            row = {k: c.get(k, '') for k in cols}
            row['mechanics'] = ' '.join(c.get('mechanics', []))
            row['race'] = c.get('race', '') or ' '.join(c.get('races', []))
            row['text'] = clean(c.get('text')); row['flavor'] = clean(c.get('flavor'))
            row['collectible'] = 'yes' if c.get('collectible') else ''
            w.writerow(row)
    print('wrote cards.csv / cards.json')
    if args.data_only:
        return

    size, ext = ('orig', 'png') if args.orig else ('512x', 'jpg')
    art_dir = os.path.join(args.out, 'art')
    os.makedirs(art_dir, exist_ok=True)
    jobs = [c['id'] for c in keep if not os.path.exists(os.path.join(art_dir, f"{c['id']}.{ext}"))]
    print(f'downloading {len(jobs)} artworks ({size}) to {art_dir} ...')

    def fetch(cid):
        dest = os.path.join(art_dir, f'{cid}.{ext}')
        try:
            data = get(ART.format(size=size, id=cid, ext=ext))
        except Exception as e:
            return f'{cid}: {e}'
        if not (data[:3] == b'\xff\xd8\xff' or data[:4] == b'\x89PNG'):
            return f'{cid}: not an image'
        with open(dest + '.part', 'wb') as f:
            f.write(data)
        os.replace(dest + '.part', dest)
        time.sleep(0.05)
        return None

    missing, done = [], 0
    with ThreadPoolExecutor(args.workers) as pool:
        for msg in pool.map(fetch, jobs):
            done += 1
            if msg:
                missing.append(msg)
            if done % 250 == 0:
                print(f'  {done}/{len(jobs)}')
    have = len([n for n in os.listdir(art_dir) if n.endswith('.' + ext)])
    print(f'done: {have} artworks in {art_dir}' + (f'; {len(missing)} had no art (e.g. {missing[0]})' if missing else ''))


if __name__ == '__main__':
    main()
