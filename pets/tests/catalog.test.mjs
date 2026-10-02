// Every egg in pets/eggs, and every monster it can hatch, must be fully built out:
// valid JSON, real asset files, chances that total 100, and a shop SQL file that matches egg.json.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PETS, validateEgg, rollOdds, shopSql } from '../helpers/validate-egg.mjs';

const folders = dir => existsSync(join(PETS, dir))
  ? readdirSync(join(PETS, dir), { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name)
  : [];
const eggKeys = folders('eggs');
const monsterKeys = folders('monsters');

for (const key of eggKeys) {
  test(`egg "${key}"`, async t => {
    const { egg, monsters, errors } = validateEgg(key);

    await t.test('passes the validator', () => {
      assert.deepEqual(errors, [], `Run: node pets/helpers/validate-egg.mjs ${key}`);
    });
    if (errors.length) return;

    await t.test('rolls each monster at its set chance (within 1 point over 10,000 rolls)', () => {
      const odds = rollOdds(egg);
      for (const c of egg.contents) {
        assert.ok(Math.abs(odds[c.monster] - c.chance) <= 1, `${c.monster}: set ${c.chance}%, rolled ${odds[c.monster].toFixed(1)}%`);
      }
    });

    await t.test('has an up-to-date shop_item.sql', () => {
      const file = join(PETS, 'eggs', key, 'shop_item.sql');
      const fix = `Run: node pets/helpers/validate-egg.mjs ${key} --sql`;
      assert.ok(existsSync(file), `shop_item.sql is missing. ${fix}`);
      // Compare without line endings: Git may check the file out with CRLF on Windows.
      const lines = text => text.replace(/\r\n/g, '\n');
      assert.equal(lines(readFileSync(file, 'utf8')), lines(shopSql(egg, monsters)), `shop_item.sql doesn't match egg.json. ${fix}`);
    });
  });
}

test('eggs/index.json lists every egg folder, and nothing else', () => {
  const listed = JSON.parse(readFileSync(join(PETS, 'eggs', 'index.json'), 'utf8'));
  assert.deepEqual([...listed].sort(), [...eggKeys].sort(), 'Add the egg key to pets/eggs/index.json (the sandbox reads it)');
});

test('the live site never loads mock or dev-only pet code (pets/DEPLOY.md)', () => {
  const site = readFileSync(join(PETS, '..', 'index.html'), 'utf8');
  for (const devOnly of ['pet-api-mock.js', 'sandbox.html', 'preview.html', 'validate-egg.mjs']) {
    assert.ok(!site.includes(devOnly), `index.html mentions ${devOnly}, which must not ship`);
  }
});

test('every monster folder is hatched by at least one egg', () => {
  const used = new Set(eggKeys.flatMap(key => validateEgg(key).egg?.contents?.map(c => c.monster) || []));
  const orphans = monsterKeys.filter(m => !used.has(m));
  assert.deepEqual(orphans, [], 'Add these monsters to an egg\'s "contents", or delete their folders');
});
