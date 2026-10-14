"""Shrink a wow.export character glTF: its geosets all index one shared vertex list (every hair, beard and
armour variant), so the .bin is huge even though a few thousand vertices are drawn. This keeps only the
vertices the kept meshes use and writes a new main .bin; animation .bins are untouched.

Usage: python tools/compact_gltf.py <in.gltf (absolute R2 uris)> <local main .bin> <out.gltf> <out.bin name> <r2 folder url>
"""
import json, struct, sys

COMP = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def main(src, binpath, out, outbin, folder):
    g = json.load(open(src)); data = open(binpath, 'rb').read()
    main_uri = g['buffers'][0]['uri']
    A, V = g['accessors'], g['bufferViews']
    def read(i):
        a = A[i]; v = V[a['bufferView']]; n = NCOMP[a['type']]; f = COMP[a['componentType']]
        size = struct.calcsize(f); stride = v.get('byteStride', size * n); off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from('<' + f * n, data, off + k * stride) for k in range(a['count'])]
    # meshes are grouped by the vertex list (POSITION accessor) they share; each list is compacted on its own
    groups = {}
    for m in g['meshes']:
        for p in m['primitives']:
            key = p['attributes']['POSITION']
            grp = groups.setdefault(key, {'attrs': set(), 'idx': set()})
            grp['attrs'].update(p['attributes'].values()); grp['idx'].add(p['indices'])
    attr_ids = set().union(*[x['attrs'] for x in groups.values()]); idx_ids = set().union(*[x['idx'] for x in groups.values()])
    out_bytes = bytearray(); new_views = []
    def add_view(raw, target=None):
        while len(out_bytes) % 4: out_bytes.append(0)
        v = {'buffer': 0, 'byteOffset': len(out_bytes), 'byteLength': len(raw)}
        if target: v['target'] = target
        out_bytes.extend(raw); new_views.append(v); return len(V) + len(new_views) - 1
    total = sum(A[k]['count'] for k in groups); kept = 0
    for key, grp in groups.items():
        used = sorted({r[0] for ii in grp['idx'] for r in read(ii)}); kept += len(used)
        remap = {old: new for new, old in enumerate(used)}
        idx_rows = {ii: read(ii) for ii in grp['idx']}
        for i in grp['attrs']:
            a = A[i]; f = COMP[a['componentType']]; rows = read(i)
            raw = b''.join(struct.pack('<' + f * len(rows[0]), *rows[o]) for o in used)
            a['bufferView'] = add_view(raw, 34962); a['byteOffset'] = 0; a['count'] = len(used)
            if 'min' in a:
                cols = list(zip(*[rows[o] for o in used])); a['min'] = [min(c) for c in cols]; a['max'] = [max(c) for c in cols]
        for ii, rows in idx_rows.items():
            a = A[ii]; fmt = 'H' if len(used) < 65536 else 'I'; a['componentType'] = 5123 if fmt == 'H' else 5125
            a['bufferView'] = add_view(struct.pack('<' + fmt * len(rows), *[remap[r[0]] for r in rows]), 34963); a['byteOffset'] = 0
    # everything else that lived in the main buffer (inverse bind matrices, etc.) is copied over as-is
    done = attr_ids | idx_ids; copied = {}
    for i, a in enumerate(A):
        if i in done or a['bufferView'] >= len(V) or V[a['bufferView']]['buffer'] != 0: continue
        vi = a['bufferView']
        if vi not in copied:
            v = V[vi]; raw = data[v.get('byteOffset', 0): v.get('byteOffset', 0) + v['byteLength']]
            copied[vi] = add_view(raw, v.get('target'))
        a['bufferView'] = copied[vi]
    # drop the old views of the main buffer by pointing them at nothing: rebuild the view list
    keep = [vi for vi, v in enumerate(V) if v['buffer'] != 0]
    all_views = [V[vi] for vi in keep] + new_views
    old_to_new = {vi: n for n, vi in enumerate(keep)}
    for n, _ in enumerate(new_views): old_to_new[len(V) + n] = len(keep) + n
    for a in A: a['bufferView'] = old_to_new[a['bufferView']]
    for im in g.get('images', []):
        if 'bufferView' in im: im['bufferView'] = old_to_new[im['bufferView']]
    g['bufferViews'] = all_views
    g['buffers'][0] = {'uri': folder.rstrip('/') + '/' + outbin, 'byteLength': len(out_bytes)}
    open(outbin, 'wb').write(out_bytes); json.dump(g, open(out, 'w'), separators=(',', ':'))
    print(f'{kept} of {total} vertices kept; main bin {len(data)//1024} KB -> {len(out_bytes)//1024} KB')

if __name__ == '__main__':
    main(*sys.argv[1:6])
