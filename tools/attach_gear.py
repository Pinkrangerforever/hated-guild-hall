"""Work out where wow.export's loose gear pieces (helm, shoulders, weapons) belong on a character's skeleton.

wow.export's glTF writes each worn item as an unattached mesh in its own local space; its "OBJ (Posed)" export
writes the same character with every item placed. This compares the two:
  1. body vertices: glTF bind position vs OBJ posed position, matched group by group (Geoset0, Torso1, ...)
  2. each item's bone = the bone that dominates the body vertices nearest the item in the posed OBJ
  3. that bone's pose = best rigid fit (Kabsch) of its strongly-weighted vertices, bind -> posed
  4. the item's pose = best rigid fit of the item's own vertices, glTF local -> posed OBJ
  5. item in bone space = inverse bind matrix of the joint * inverse(bone pose) * item pose
and stores {joint, matrix} in each item node's extras.attach, so the board can pin it on exactly.

Usage: python tools/attach_gear.py <full source .gltf> <its main .bin> <posed .obj> <trimmed .gltf to update>
"""
import json, struct, sys
import numpy as np

C = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}
N = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def reader(g, data):
    A, V = g['accessors'], g['bufferViews']
    def rd(i):
        a = A[i]; v = V[a['bufferView']]; n = N[a['type']]; f = C[a['componentType']]
        s = struct.calcsize(f); st = v.get('byteStride', s * n); o = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        return np.array([struct.unpack_from('<' + f * n, data, o + k * st) for k in range(a['count'])], dtype=float)
    return rd

def load_obj(path):
    V, faces, cur = [], {}, None
    for line in open(path):
        if line.startswith('v '): V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('g '): cur = line[2:].strip(); faces.setdefault(cur, set())
        elif line.startswith('f ') and cur is not None:
            for t in line.split()[1:]: faces[cur].add(int(t.split('/')[0]) - 1)
    return np.array(V), {k: sorted(v) for k, v in faces.items()}

def kabsch(P, Q):
    """R, t with R @ p + t ~= q (rotation only, no reflection)"""
    pc, qc = P.mean(0), Q.mean(0)
    H = (P - pc).T @ (Q - qc); U, S, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T)); D = np.diag([1, 1, d])
    R = Vt.T @ D @ U.T; return R, qc - R @ pc

def mat(R, t): M = np.eye(4); M[:3, :3] = R; M[:3, 3] = t; return M

def main(src, binf, objf, trimmed):
    g = json.load(open(src)); rd = reader(g, open(binf, 'rb').read())
    OV, OG = load_obj(objf)
    nodes = g['nodes']; skin = g['skins'][0]
    ibm = rd(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)   # column-major -> row-major
    # 1) body correspondences, group by group
    bind_pts, posed_pts, joints, weights = [], [], [], []
    items = {}
    for n in nodes:
        if 'mesh' not in n: continue
        name = n['name']; p = g['meshes'][n['mesh']]['primitives'][0]
        if 'Item' in name: items[name] = p; continue
        grp = name.split('_')[-1]
        if grp not in OG or grp.startswith('HeadSwap'): continue   # alternate heads aren't posed reliably in the OBJ
        idx = sorted(set(rd(p['indices']).astype(int).ravel()))
        if len(idx) != len(OG[grp]): print('skip body group', grp, len(idx), len(OG[grp])); continue
        pos = rd(p['attributes']['POSITION']); J = rd(p['attributes']['JOINTS_0']); W = rd(p['attributes']['WEIGHTS_0'])
        if W.max() > 1.5: W = W / 255.0
        bind_pts.append(pos[idx]); posed_pts.append(OV[OG[grp]]); joints.append(J[idx]); weights.append(W[idx])
    B, P, J, W = (np.concatenate(x) for x in (bind_pts, posed_pts, joints, weights))
    # sanity: the whole body as one rigid fit should be poor-ish but finite; per bone fits are what we use
    def bone_pose(j):
        sel = [(k) for k in range(len(B)) if any(J[k][c] == j and W[k][c] > 0.85 for c in range(4))]
        if len(sel) < 4: return None, len(sel)
        R, t = kabsch(B[sel], P[sel]); err = np.abs((B[sel] @ R.T + t) - P[sel]).max()
        return (mat(R, t), err), len(sel)
    out = {}
    for name, p in items.items():
        if name not in OG: print('not in OBJ:', name); continue
        loc = rd(p['attributes']['POSITION']); idx = sorted(set(rd(p['indices']).astype(int).ravel()))
        if len(idx) != len(OG[name]): print('vertex mismatch', name); continue
        X = np.hstack([loc[idx], np.ones((len(idx), 1))]); sol, *_ = np.linalg.lstsq(X, OV[OG[name]], rcond=None)
        item_pose = np.eye(4); item_pose[:3, :] = sol.T
        ierr = np.abs(X @ sol - OV[OG[name]]).max()
        # 2) the dominant bone among the posed body vertices nearest the item
        c = OV[OG[name]].mean(0); near = np.argsort(np.linalg.norm(P - c, axis=1))[:40]
        votes = {}
        for k in near:
            j = int(J[k][np.argmax(W[k])]); votes[j] = votes.get(j, 0) + 1
        best = None
        if name.startswith('Head'):
            # helms: the bone that carries the crown of the head (the 40 highest body vertices at bind)
            top = np.argsort(-B[:, 1])[:40]; hv = {}
            for k in top:
                for c4 in range(4):
                    if W[k][c4] > 0.3: hv[int(J[k][c4])] = hv.get(int(J[k][c4]), 0) + W[k][c4]
            for j, _ in sorted(hv.items(), key=lambda x: -x[1]):
                bp, n_sel = bone_pose(j)
                if bp: best = (j, bp); print(f'  head bone {j} (crown weight {hv[j]:.1f})'); break
        for j, _ in ([] if best else sorted(votes.items(), key=lambda x: -x[1])):
            bp, n_sel = bone_pose(j)
            if bp: best = (j, bp); break
        if not best:
            sib = next((k for k in out if k.rsplit('_', 1)[0] == name.rsplit('_', 1)[0]), None)
            if sib: out[name] = dict(out[sib]); print(name, ': follows', sib)
            else: print('no bone for', name)
            continue
        j, (bone_M, berr) = best
        bind_item = np.linalg.inv(bone_M) @ item_pose          # item local -> bind (model) space
        if name.startswith('Head'):
            # helms sit on the body's centre line (z = 0 in bind space); some exports push them sideways
            hz = (np.hstack([loc[idx], np.ones((len(idx), 1))]) @ bind_item.T)[:, 2].mean()
            if abs(hz) > 0.05: S = np.eye(4); S[2, 3] = -hz; bind_item = S @ bind_item; print(f'  helm re-centred by {-hz:.3f}')
        local = ibm[j] @ bind_item                              # -> joint space
        out[name] = {'joint': j, 'matrix': local.T.ravel().round(6).tolist()}   # column-major for three.js
        print(f'{name}: joint {j}, item fit {ierr:.4f}, bone fit {berr:.4f}')
    t = json.load(open(trimmed))
    for n in t['nodes']:
        if n.get('name') in out: n.setdefault('extras', {})['attach'] = out[n['name']]
    json.dump(t, open(trimmed, 'w'), separators=(',', ':'))
    print('wrote', len(out), 'attachments into', trimmed)

if __name__ == '__main__':
    main(*sys.argv[1:5])
