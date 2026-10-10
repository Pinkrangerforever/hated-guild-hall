"""Trim a wow.export glTF down to a few animations for the website.

wow.export writes every animation (77 for the gryphon pet) into the .gltf plus one .bin per clip,
which is ~6 MB to load. This keeps only the clips (and meshes) we use, drops unused accessors/
bufferViews/buffers/materials/textures/images, and rewrites the remaining buffer + texture URIs to
absolute R2 URLs, so the trimmed .gltf can live in the repo while the heavy files stay on R2.

Usage:
  python tools/trim_gltf.py <source.gltf> <r2 folder url> <output.gltf> [options] "Stand (ID 0" "Hover (ID 193" ...

Clips: each argument is matched as a prefix of the animation name (variation 0 is listed first by
wow.export, so "Stand (ID 0 variation 0)" etc.). Output names are shortened to the part before
" (ID", e.g. "Stand". To keep two variations of one animation, rename with "=>":
"Stand (ID 0 variation 1=>StandAlt".

Options:
  --image=<original.png>=<uri>   use a different file for a texture (e.g. a downscaled JPEG kept in
                                 the repo); a relative uri resolves next to the output .gltf
  --drop-mesh=<node name>        remove a mesh node (e.g. a duplicate or effect geoset)
"""
import json
import sys


def main():
    args = sys.argv[1:]
    options = [a for a in args if a.startswith('--')]
    positional = [a for a in args if not a.startswith('--')]
    if len(positional) < 4:
        print(__doc__)
        sys.exit(1)
    src, r2_base, out, *clip_prefixes = positional
    r2_base = r2_base.rstrip('/') + '/'
    image_overrides = dict(o[len('--image='):].split('=', 1) for o in options if o.startswith('--image='))
    drop_meshes = {o[len('--drop-mesh='):] for o in options if o.startswith('--drop-mesh=')}
    g = json.load(open(src, encoding='utf-8'))

    # 1) Keep the requested animations (first match per prefix, in the order requested)
    kept = []
    for arg in clip_prefixes:
        prefix, _, rename = arg.partition('=>')
        match = next((a for a in g.get('animations', []) if a.get('name', '').startswith(prefix)), None)
        if not match:
            sys.exit(f'No animation starts with {prefix!r}')
        match = dict(match)
        match['name'] = rename or match['name'].split(' (ID')[0]
        if any(k['name'] == match['name'] for k in kept):
            sys.exit(f'Duplicate clip name {match["name"]!r} - rename one with "=>"')
        kept.append(match)
    g['animations'] = kept

    # 2) Drop requested mesh nodes, then any meshes no node uses
    for node in g.get('nodes', []):
        if node.get('name') in drop_meshes and 'mesh' in node:
            del node['mesh']
            node.pop('skin', None)
    used_meshes = sorted({n['mesh'] for n in g.get('nodes', []) if 'mesh' in n})
    mesh_map = {old: new for new, old in enumerate(used_meshes)}
    g['meshes'] = [g['meshes'][old] for old in used_meshes]
    for node in g.get('nodes', []):
        if 'mesh' in node:
            node['mesh'] = mesh_map[node['mesh']]

    # 3) Find every accessor still referenced by meshes, skins and the kept animations
    used_acc = set()
    for mesh in g.get('meshes', []):
        for prim in mesh['primitives']:
            used_acc.update(prim.get('attributes', {}).values())
            if 'indices' in prim:
                used_acc.add(prim['indices'])
            for target in prim.get('targets', []):
                used_acc.update(target.values())
    for skin in g.get('skins', []):
        if 'inverseBindMatrices' in skin:
            used_acc.add(skin['inverseBindMatrices'])
    for anim in kept:
        for s in anim['samplers']:
            used_acc.update([s['input'], s['output']])

    # 4) Reindex accessors -> bufferViews -> buffers, dropping everything unused
    acc_map = {old: new for new, old in enumerate(sorted(used_acc))}
    accessors = [g['accessors'][old] for old in sorted(used_acc)]

    used_views = {a['bufferView'] for a in accessors if 'bufferView' in a}
    used_views.update(img['bufferView'] for img in g.get('images', []) if 'bufferView' in img)
    view_map = {old: new for new, old in enumerate(sorted(used_views))}
    views = [g['bufferViews'][old] for old in sorted(used_views)]

    used_bufs = {v['buffer'] for v in views}
    buf_map = {old: new for new, old in enumerate(sorted(used_bufs))}
    buffers = [dict(g['buffers'][old]) for old in sorted(used_bufs)]

    for a in accessors:
        if 'bufferView' in a:
            a['bufferView'] = view_map[a['bufferView']]
    for v in views:
        v['buffer'] = buf_map[v['buffer']]
    for img in g.get('images', []):
        if 'bufferView' in img:
            img['bufferView'] = view_map[img['bufferView']]

    for mesh in g.get('meshes', []):
        for prim in mesh['primitives']:
            prim['attributes'] = {k: acc_map[v] for k, v in prim['attributes'].items()}
            if 'indices' in prim:
                prim['indices'] = acc_map[prim['indices']]
            if 'targets' in prim:
                prim['targets'] = [{k: acc_map[v] for k, v in t.items()} for t in prim['targets']]
    for skin in g.get('skins', []):
        if 'inverseBindMatrices' in skin:
            skin['inverseBindMatrices'] = acc_map[skin['inverseBindMatrices']]
    for anim in kept:
        for s in anim['samplers']:
            s['input'] = acc_map[s['input']]
            s['output'] = acc_map[s['output']]
    g['accessors'], g['bufferViews'], g['buffers'] = accessors, views, buffers

    # 5) Drop materials/textures/images nothing uses (so unused textures are never downloaded)
    if 'materials' in g:
        used_mats = sorted({p['material'] for m in g['meshes'] for p in m['primitives'] if 'material' in p})
        mat_map = {old: new for new, old in enumerate(used_mats)}
        g['materials'] = [g['materials'][old] for old in used_mats]
        for m in g['meshes']:
            for p in m['primitives']:
                if 'material' in p:
                    p['material'] = mat_map[p['material']]

        def texture_refs(mat):
            refs = []
            for holder in (mat, mat.get('pbrMetallicRoughness', {})):
                for key, val in holder.items():
                    if isinstance(val, dict) and 'index' in val and key.endswith('Texture'):
                        refs.append(val)
            return refs

        used_tex = sorted({r['index'] for mat in g['materials'] for r in texture_refs(mat)})
        tex_map = {old: new for new, old in enumerate(used_tex)}
        for mat in g['materials']:
            for r in texture_refs(mat):
                r['index'] = tex_map[r['index']]
        g['textures'] = [g['textures'][old] for old in used_tex]

        used_imgs = sorted({t['source'] for t in g['textures'] if 'source' in t})
        img_map = {old: new for new, old in enumerate(used_imgs)}
        g['images'] = [g['images'][old] for old in used_imgs]
        for t in g['textures']:
            if 'source' in t:
                t['source'] = img_map[t['source']]

    # 6) Point the remaining .bin and texture files at R2 (or at an override)
    for b in buffers:
        if 'uri' in b and not b['uri'].startswith(('http', 'data:')):
            b['uri'] = r2_base + b['uri']
    for img in g.get('images', []):
        uri = img.get('uri')
        if uri in image_overrides:
            img['uri'] = image_overrides[uri]
            img.pop('mimeType', None)
        elif uri and not uri.startswith(('http', 'data:')):
            img['uri'] = r2_base + uri

    with open(out, 'w', encoding='utf-8') as f:
        json.dump(g, f, separators=(',', ':'))

    total_bin = sum(b.get('byteLength', 0) for b in buffers)
    print(f'kept {len(kept)} animations: {[a["name"] for a in kept]}')
    print(f'meshes {len(g["meshes"])}, materials {len(g.get("materials", []))}, images {[i.get("uri", "").split("/")[-1] for i in g.get("images", [])]}')
    print(f'accessors {len(accessors)}, bufferViews {len(views)}, buffers {len(buffers)} ({total_bin/1024:.0f} KB of .bin)')


if __name__ == '__main__':
    main()
