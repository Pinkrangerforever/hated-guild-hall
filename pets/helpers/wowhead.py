"""Looks up a WoW creature on Wowhead and downloads its model image and sounds for a pet egg or monster.
See pets/README.md -> Getting art. Downloads go into the repo; never hotlink them.

    python pets/helpers/wowhead.py search "baby gorilla"
    python pets/helpers/wowhead.py npc 269986                      # or the NPC's Wowhead URL
    python pets/helpers/wowhead.py npc 269986 --image pets/monsters/<key>/assets/idle.webp
    python pets/helpers/wowhead.py npc 269986 --sound 3 --out pets/monsters/<key>/assets/call.ogg
    python pets/helpers/wowhead.py image 21362 pets/eggs/<key>/assets/idle.webp   # by model display ID or webthumbs URL

`npc` lists the creature's model display ID and its sound files, numbered; --sound picks one by number.
The image is the model's 300x300 still render, cropped to the creature, squared and saved as WebP.
Needs Pillow (pip install pillow) for --image and `image`.
"""
import argparse
import io
import json
import re
import struct
import sys
import urllib.parse
import urllib.request

HEADERS = {'User-Agent': 'Mozilla/5.0 (hated-guild-hall pet tools)'}


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30) as res:
        return res.read()


def thumb_url(display_id):
    # Wowhead keeps a still render of each model, bucketed by the display ID's low byte.
    return f'https://wow.zamimg.com/modelviewer/live/webthumbs/npc/{display_id & 255}/{display_id}.webp'


def _json_array_after(html, start):
    """The JSON array that begins at the first '[' after start."""
    i = html.index('[', start)
    depth = 0
    for j in range(i, len(html)):
        if html[j] == '[':
            depth += 1
        elif html[j] == ']':
            depth -= 1
            if depth == 0:
                return json.loads(html[i:j + 1])
    raise ValueError('unterminated array')


def parse_npc(html):
    """Name, model display ID and unique sound files from a Wowhead NPC page."""
    title = re.search(r'<title>(.*?) - NPC - ', html)
    display = re.search(r'displayId = (\d+)', html)
    sounds, seen = [], {}
    tab = html.find("id: 'sounds'")
    if tab != -1:
        for entry in _json_array_after(html, html.index('data:', tab)):
            for f in entry.get('files', []):
                url = f.get('url')
                if not url:
                    continue
                if url not in seen:
                    seen[url] = {'n': len(sounds) + 1, 'title': f.get('title', ''), 'url': url, 'activities': []}
                    sounds.append(seen[url])
                if entry.get('activity') not in seen[url]['activities']:
                    seen[url]['activities'].append(entry.get('activity'))
    display_id = int(display.group(1)) if display else None
    return {
        'name': title.group(1) if title else None,
        'display_id': display_id,
        'image_url': thumb_url(display_id) if display_id else None,
        'sounds': sounds,
    }


def ogg_seconds(data):
    """Length of an Ogg Vorbis file, from its sample rate and last granule position."""
    rate = struct.unpack('<I', data[40:44])[0]
    last = data.rfind(b'OggS')
    return struct.unpack('<q', data[last + 6:last + 14])[0] / rate


def save_image(url, out):
    from PIL import Image
    im = Image.open(io.BytesIO(fetch(url))).convert('RGBA')
    l, t, r, b = im.getchannel('A').getbbox()
    side = max(r - l, b - t)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(im.crop((l, t, r, b)), ((side - (r - l)) // 2, (side - (b - t)) // 2))
    square.save(out, quality=90, method=6)
    touches = [name for name, edge in (('left', l == 0), ('top', t == 0), ('right', r == im.width), ('bottom', b == im.height)) if edge]
    print(f'Saved {out} ({side}x{side}) from {url}')
    if touches:
        print(f'Note: the model runs off the render\'s {", ".join(touches)} edge, so part of it is cut off.')


def npc_id(value):
    m = re.search(r'npc=(\d+)', value)
    return int(m.group(1)) if m else int(value)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('search', help='find NPCs by name')
    s.add_argument('query')
    n = sub.add_parser('npc', help='show an NPC, and optionally download its image or a sound')
    n.add_argument('npc', help='NPC id or Wowhead URL')
    n.add_argument('--image', metavar='OUT', help='save the model image here (.webp)')
    n.add_argument('--sound', type=int, metavar='N', help='download sound number N from the list')
    n.add_argument('--out', help='where to save the sound (.ogg)')
    i = sub.add_parser('image', help='save a model image by display ID or webthumbs URL')
    i.add_argument('display', help='model display ID, or a wow.zamimg.com webthumbs URL')
    i.add_argument('out')
    t = sub.add_parser('parse', help='print what a saved NPC page contains, as JSON (used by the tests)')
    t.add_argument('file')
    a = p.parse_args()

    if a.cmd == 'parse':
        with open(a.file, encoding='utf-8') as f:
            print(json.dumps(parse_npc(f.read())))
    elif a.cmd == 'search':
        q = urllib.parse.quote(a.query)
        results = json.loads(fetch(f'https://www.wowhead.com/search/suggestions-template?q={q}')).get('results', [])
        npcs = [r for r in results if r.get('typeName') == 'NPC']
        for r in npcs:
            print(f'{r["id"]:>8}  {r["name"]}')
        if not npcs:
            print('No NPCs found. Try fewer or different words.')
    elif a.cmd == 'image':
        url = a.display if a.display.startswith('http') else thumb_url(int(a.display))
        save_image(url, a.out)
    else:
        nid = npc_id(a.npc)
        info = parse_npc(fetch(f'https://www.wowhead.com/npc={nid}').decode('utf-8', 'ignore'))
        print(f'{info["name"]} (NPC {nid}), model display {info["display_id"]}')
        print(f'  image: {info["image_url"]}')
        for snd in info['sounds']:
            print(f'  sound {snd["n"]}: {snd["title"]} ({", ".join(snd["activities"])})  {snd["url"]}')
        if not info['sounds']:
            print('  no sounds listed')
        if a.image:
            if not info['image_url']:
                sys.exit('This page has no model display ID.')
            save_image(info['image_url'], a.image)
        if a.sound:
            if not a.out:
                sys.exit('--sound needs --out <file.ogg>')
            match = [s for s in info['sounds'] if s['n'] == a.sound]
            if not match:
                sys.exit(f'No sound {a.sound}; pick a number from the list above.')
            data = fetch(match[0]['url'])
            with open(a.out, 'wb') as f:
                f.write(data)
            print(f'Saved {a.out}: {len(data) // 1024} KB, {ogg_seconds(data):.1f} s. Keep calls under 100 KB.')


if __name__ == '__main__':
    main()
