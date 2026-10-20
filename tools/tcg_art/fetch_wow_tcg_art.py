"""Fetch the World of Warcraft TCG high-resolution scans and cut out each card's artwork.

Source: the community WoW TCG Scan Project (https://www.reddit.com/r/wowtcg/comments/6myzka/the_wow_tcg_scan_project/),
public Google Drive folders of 745x1040 scans. The art is Blizzard's / its artists'; this is for the guild's own
non-commercial use. Nothing is written into the repo: scans and art go to OUT (default Documents\\WoW TCG Art).

    python tools/tcg_art/fetch_wow_tcg_art.py                    # every set (basic sets + raids/dungeons)
    python tools/tcg_art/fetch_wow_tcg_art.py --sets "Heroes of Azeroth" "The Molten Core"
    python tools/tcg_art/fetch_wow_tcg_art.py --list              # just list the sets
    python tools/tcg_art/fetch_wow_tcg_art.py --crop-only         # re-cut the art from scans already downloaded

Output:
    OUT/scans/<set>/<card>.png        the full card scans
    OUT/art/<set>/<card>.jpg          the artwork only (frame, text and stats cut away)
    OUT/index.csv                     set, card, scan and art paths, art size

Safe to stop and re-run: anything already downloaded / cut is skipped. Downloads are spaced out to be polite.
"""
import argparse, csv, html, os, re, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

# the project's public folders (folder id, resource key)
ROOTS = {
    'basic':  ('0B3PgzLuAh5T6d2hid194ZnA1NE0', '0-7MVjXbHMSPmEhR4nXdIjuQ'),   # Heroes of Azeroth ... Reign of Fire
    'raids':  ('0B3PgzLuAh5T6Um9tQ2Y3NG16aWM', '0-e9SqS2lhtO4-RW7YKnqJ5A'),   # Molten Core, Onyxia, Naxxramas, dungeon decks...
    'extras': ('1-4kWqXEWtZhM2PMZsUGEBJLtmGnr1cKF', None),                     # promos, starters, tokens, treasure...
}
UA = {'User-Agent': 'Mozilla/5.0 (HatedGuild card-art fetcher)'}


def http(url, keys=None, timeout=90):
    req = urllib.request.Request(url, headers=UA)
    if keys:
        req.add_header('X-Goog-Drive-Resource-Keys', ','.join(f'{i}/{k}' for i, k in keys))
    for attempt in range(4):
        try:
            return urllib.request.urlopen(req, timeout=timeout).read()
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(2 + attempt * 3)


def list_folder(fid, rkey=None):
    """[(name, kind, id, resource key)] for a public Drive folder."""
    page = http(f'https://drive.google.com/embeddedfolderview?id={fid}', [(fid, rkey)] if rkey else None).decode('utf-8', 'ignore')
    out = []
    for href, name in re.findall(r'<a href="(https://drive\.google\.com/[^"]+)"[^>]*>.*?<div class="flip-entry-title">([^<]+)</div>', page, re.S):
        href, name = html.unescape(href), html.unescape(name).strip()
        m = re.search(r'/folders/([\w-]+)', href) or re.search(r'/d/([\w-]+)', href) or re.search(r'[?&]id=([\w-]+)', href)
        rk = re.search(r'resourcekey=([\w-]+)', href)
        if m:
            out.append((name, 'folder' if '/folders/' in href else 'file', m.group(1), rk.group(1) if rk else None))
    return out


def safe(name):
    return re.sub(r'[<>:"/\\|?*]+', '_', name).strip(' .') or 'card'


# ---------- cutting out the art ----------
# Every WoW TCG card (2006-2013) has the same layout: title bar on top, the art window, then the type bar and the
# text box. The art window's edges are the strongest straight lines in those regions, so they're found per card
# (items have a column of icons on the right, which this also finds and leaves out).
def art_box(img):
    a = np.asarray(img.convert('L'), dtype=np.float32)
    h, w = a.shape
    def row_edges(y0, y1, x0, x1):
        band = a[y0:y1, x0:x1]
        return np.abs(np.diff(band, axis=0)).mean(axis=1)            # strength of a horizontal edge at each row
    def col_edges(x0, x1, y0, y1):
        band = a[y0:y1, x0:x1]
        return np.abs(np.diff(band, axis=1)).mean(axis=0)
    xa, xb = int(w * 0.25), int(w * 0.75)                             # middle of the card (clear of the cost / faction badges)
    top_r = row_edges(int(h * 0.06), int(h * 0.16), xa, xb)
    top = int(h * 0.06) + int(np.argmax(top_r)) + 2
    bot_r = row_edges(int(h * 0.55), int(h * 0.70), xa, xb)
    strong = np.nonzero(bot_r > bot_r.max() * 0.55)[0]                # the type bar has two edges: take its top one
    bottom = int(h * 0.55) + int(strong[0] if len(strong) else np.argmax(bot_r)) - 1
    ya, yb = top + 20, bottom - 20
    left_c = col_edges(0, int(w * 0.10), ya, yb)
    left = int(np.argmax(left_c)) + 2
    right_c = col_edges(int(w * 0.80), w, ya, yb)
    right = int(w * 0.80) + int(np.argmax(right_c)) - 1
    # sanity: fall back to the standard window if the detection looks off
    std = (int(w * 0.040), int(h * 0.090), int(w * 0.958), int(h * 0.625))
    box = (left + 3, top + 3, right - 3, bottom - 3)                   # a few pixels in, so no frame line shows
    if not (w * 0.6 < right - left < w * 0.97 and h * 0.40 < bottom - top < h * 0.62):
        box = std
    return box


def full_art_box(img):
    """Raid boss card backs are full-art: everything above the text box at the bottom is the picture."""
    a = np.asarray(img.convert('L'), dtype=np.float32)
    h, w = a.shape
    # the name banner is a dark band across the bottom: cut just above the first long run of rows much darker than
    # the art (edges don't work here - busy art like fire has stronger edges than the banner)
    mid = a[:, int(w * 0.3):int(w * 0.7)].mean(axis=1)
    art_level = np.median(mid[int(h * 0.2):int(h * 0.6)])
    bottom = int(h * 0.92)
    run = 0
    for y in range(int(h * 0.65), int(h * 0.95)):
        run = run + 1 if mid[y] < art_level * 0.55 else 0
        if run >= 12:
            bottom = y - run - 4
            break
    border = int(w * 0.045)                                               # inside the rounded gold border
    return (border, border, w - border, max(bottom, int(h * 0.6)))


def cut(scan_path, art_path):
    img = Image.open(scan_path).convert('RGB')
    name = os.path.basename(scan_path).lower()
    box = full_art_box(img) if re.search(r'back\s*side|- back(\.|$)', name) else art_box(img)
    art = img.crop(box)
    os.makedirs(os.path.dirname(art_path), exist_ok=True)
    art.save(art_path, quality=92)
    return art.size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=os.path.join(os.path.expanduser('~'), 'Documents', 'WoW TCG Art'))
    ap.add_argument('--groups', nargs='*', default=['basic', 'raids'], choices=list(ROOTS), help='which folders (default: basic raids)')
    ap.add_argument('--sets', nargs='*', help='only these sets (names as listed by --list)')
    ap.add_argument('--list', action='store_true', help='list the sets and stop')
    ap.add_argument('--crop-only', action='store_true', help="don't download, just cut art from scans already here")
    ap.add_argument('--workers', type=int, default=4)
    args = ap.parse_args()

    scans_dir, art_dir = os.path.join(args.out, 'scans'), os.path.join(args.out, 'art')
    sets = []
    if not args.crop_only:
        for g in args.groups:
            fid, rk = ROOTS[g]
            for name, kind, i, k in list_folder(fid, rk):
                if kind == 'folder':
                    sets.append((g, name, i, k))
        if args.list:
            for g, name, _, _ in sets:
                print(f'{g:7} {name}')
            return
        if args.sets:
            want = {s.lower() for s in args.sets}
            sets = [s for s in sets if s[1].lower() in want]
            if not sets:
                sys.exit('none of those sets were found - try --list')

        jobs = []
        for g, name, i, k in sets:
            files = list_folder(i, k)
            # some sets hold sub-folders (e.g. tokens); go one level down
            for sub in [f for f in files if f[1] == 'folder']:
                files += [(f'{sub[0]} - {n}', kd, fi, fk) for n, kd, fi, fk in list_folder(sub[2], sub[3]) if kd == 'file']
            pngs = [f for f in files if f[1] == 'file' and re.search(r'\.(png|jpe?g)$', f[0], re.I)]
            print(f'{name}: {len(pngs)} cards')
            for n, _, fi, fk in pngs:
                dest = os.path.join(scans_dir, safe(name), safe(n))
                if not os.path.exists(dest):
                    jobs.append((dest, fi, fk))

        print(f'downloading {len(jobs)} scans to {scans_dir} ...')
        def fetch(job):
            dest, fi, fk = job
            url = f'https://drive.google.com/uc?export=download&id={fi}' + (f'&resourcekey={fk}' if fk else '')
            data = http(url, [(fi, fk)] if fk else None)
            if data[:4] not in (b'\x89PNG', b'\xff\xd8\xff\xe0', b'\xff\xd8\xff\xe1', b'\xff\xd8\xff\xdb'):
                return f'skipped (not an image - Drive may be rate limiting): {dest}'
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest + '.part', 'wb') as f:
                f.write(data)
            os.replace(dest + '.part', dest)
            time.sleep(0.4)
            return None
        done = 0
        with ThreadPoolExecutor(args.workers) as pool:
            for msg in pool.map(fetch, jobs):
                done += 1
                if msg:
                    print('  ' + msg)
                if done % 50 == 0:
                    print(f'  {done}/{len(jobs)}')

    # cut the art from every scan we have
    rows, n_new = [], 0
    for root, _, files in os.walk(scans_dir):
        for f in sorted(files):
            if not re.search(r'\.(png|jpe?g)$', f, re.I):
                continue
            set_name = os.path.relpath(root, scans_dir)
            card = os.path.splitext(f)[0]
            scan = os.path.join(root, f)
            art = os.path.join(art_dir, set_name, card + '.jpg')
            try:
                if not os.path.exists(art):
                    size = cut(scan, art); n_new += 1
                else:
                    size = Image.open(art).size
            except Exception as e:
                print(f'  could not cut {scan}: {e}')
                continue
            rows.append({'set': set_name, 'card': card, 'scan': scan, 'art': art, 'art_w': size[0], 'art_h': size[1]})
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, 'index.csv'), 'w', newline='', encoding='utf-8') as fh:
        wr = csv.DictWriter(fh, fieldnames=['set', 'card', 'scan', 'art', 'art_w', 'art_h'])
        wr.writeheader(); wr.writerows(rows)
    print(f'cut {n_new} new artworks; {len(rows)} in total. Index: {os.path.join(args.out, "index.csv")}')


if __name__ == '__main__':
    main()
