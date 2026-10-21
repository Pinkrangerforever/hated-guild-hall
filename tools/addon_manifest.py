"""Write addons/HatedCompanion/files.json: every file the addon ships (except Plan/, which the website makes).

The website's addon download / CurseForge publish reads this list fresh from the server, so a page that has been
open since before an update still packs exactly the files that are on the site now. Run it after adding or
removing addon files:  python tools/addon_manifest.py
"""
import json, os

ROOT = os.path.join(os.path.dirname(__file__), '..', 'addons', 'HatedCompanion')
files = []
for d, _, names in os.walk(ROOT):
    rel = os.path.relpath(d, ROOT).replace('\\', '/')
    if rel.split('/')[0] == 'Plan':
        continue
    for n in names:
        if n == 'files.json':
            continue
        files.append(n if rel == '.' else f'{rel}/{n}')
# the .toc first (its version is read first), then everything else in a stable order
files.sort(key=lambda f: (not f.endswith('.toc'), f.lower()))
with open(os.path.join(ROOT, 'files.json'), 'w', encoding='utf-8', newline='\n') as f:
    json.dump(files, f, indent=0)
print(f'{len(files)} files listed in addons/HatedCompanion/files.json')
