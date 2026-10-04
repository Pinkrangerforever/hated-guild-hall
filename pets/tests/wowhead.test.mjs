// pets/helpers/wowhead.py reads Wowhead NPC pages. This checks its parsing offline, against a trimmed saved page,
// so a change in its logic is caught without the network. (If Wowhead changes its page format, update the fixture.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, '..', 'helpers', 'wowhead.py');
const python = ['python', 'python3'].find(cmd => { try { execFileSync(cmd, ['--version']); return true; } catch { return false; } });

test('reads the name, model and de-duplicated sounds from an NPC page', { skip: !python && 'Python not found' }, () => {
  const info = JSON.parse(execFileSync(python, [script, 'parse', join(here, 'fixtures', 'wowhead-npc.html')], { encoding: 'utf8' }));
  assert.equal(info.name, 'Baby Gorilla');
  assert.equal(info.display_id, 21362);
  assert.equal(info.image_url, 'https://wow.zamimg.com/modelviewer/live/webthumbs/npc/114/21362.webp'); // 21362 & 255 = 114
  assert.deepEqual(info.sounds.map(s => [s.n, s.title, s.activities]), [
    [1, 'PetGorillaC', ['Greeting', 'Death']],
    [2, 'PetGorillaB', ['Greeting']],
  ]);
});
