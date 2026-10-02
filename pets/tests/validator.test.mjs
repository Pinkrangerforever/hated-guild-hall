// The validator must accept a complete egg and catch each way an egg can be half-built.
// Each test builds a known-good egg in a temp folder, breaks one thing, and checks the error.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { PETS, validateEgg } from '../helpers/validate-egg.mjs';

function goodEgg() {
  return {
    key: 'test-egg', name: 'Test Egg', description: 'For tests.', price: 100,
    shop_image: 'assets/shop.png',
    animations: { idle: { src: 'assets/idle.png' } },
    hatch: { actions: ['visit_calendar', 'open_shop', 'rsvp_event'], distinct_actions: 2 },
    contents: [{ monster: 'test-whelp', chance: 75 }, { monster: 'test-drake', chance: 25 }],
    xp_curve: [60, 100, 140],
  };
}
function goodMonster(key) {
  return {
    key, name: 'Test', type: 'Dragonkin', rarity: 'common', description: 'For tests.',
    animations: { idle: { src: 'assets/idle.png', frames: 4, fps: 6, frame_width: 64, frame_height: 64 } },
  };
}

// Just enough of a PNG for the validator to read its size.
function pngHeader(width, height) {
  const b = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).copy(b, 0);
  b.write('IHDR', 12, 'latin1');
  b.writeUInt32BE(width, 16);
  b.writeUInt32BE(height, 20);
  return b;
}

// Writes a pets folder to a temp dir; `breakIt` edits the egg and monsters before they're saved.
function check(breakIt = () => {}, { skipFiles = [], shopSize = [480, 160], extraFiles = [] } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'pets-'));
  try {
    copyFileSync(join(PETS, 'hatch-actions.json'), join(root, 'hatch-actions.json'));
    const egg = goodEgg();
    const monsters = { 'test-whelp': goodMonster('test-whelp'), 'test-drake': goodMonster('test-drake') };
    const traits = JSON.parse(readFileSync(join(PETS, 'traits.json'), 'utf8'));
    breakIt(egg, monsters, traits);
    writeFileSync(join(root, 'traits.json'), JSON.stringify(traits));
    const write = (dir, file, json) => {
      mkdirSync(join(root, dir, 'assets'), { recursive: true });
      if (!skipFiles.includes(`${dir}/assets/idle.png`)) writeFileSync(join(root, dir, 'assets', 'idle.png'), 'png');
      if (!skipFiles.includes(`${dir}/${file}`)) writeFileSync(join(root, dir, file), JSON.stringify(json));
    };
    write('eggs/test-egg', 'egg.json', egg);
    for (const file of extraFiles) {
      mkdirSync(dirname(join(root, file)), { recursive: true });
      writeFileSync(join(root, file), 'png');
    }
    if (!skipFiles.includes('eggs/test-egg/assets/shop.png')) writeFileSync(join(root, 'eggs/test-egg/assets/shop.png'), pngHeader(...shopSize));
    for (const [key, m] of Object.entries(monsters)) write(`monsters/${key}`, 'monster.json', m);
    return validateEgg('test-egg', root).errors;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
const expectError = (errors, fragment) =>
  assert.ok(errors.some(e => e.includes(fragment)), `expected an error containing "${fragment}", got:\n${errors.join('\n') || '(none)'}`);

test('a complete egg passes', () => {
  assert.deepEqual(check(), []);
});

const broken = [
  ['chances that do not total 100', egg => { egg.contents[1].chance = 20; }, 'add up to 95%'],
  ['a zero chance', egg => { egg.contents[1].chance = 0; egg.contents[0].chance = 100; }, 'needs a chance above 0'],
  ['a monster listed twice', egg => { egg.contents[1].monster = 'test-whelp'; }, 'listed twice'],
  ['no contents', egg => { egg.contents = []; }, 'lists no monsters'],
  ['an unknown hatch action', egg => { egg.hatch.actions[1] = 'open_shopp'; }, '"open_shopp" is not in'],
  ['a hatch action listed twice', egg => { egg.hatch.actions[1] = 'visit_calendar'; }, 'lists an action twice'],
  ['more required actions than listed', egg => { egg.hatch.distinct_actions = 5; }, 'must be between 1 and the 3'],
  ['a missing price', egg => { delete egg.price; }, '"price" must be'],
  ['an empty name', egg => { egg.name = ''; }, '"name" is empty'],
  ['a key that does not match its folder', egg => { egg.key = 'other-egg'; }, 'but the folder is'],
  ['no egg idle animation', egg => { egg.animations = { ready: { src: 'assets/idle.png' } }; }, 'needs an "idle" animation'],
  ['an empty xp curve', egg => { egg.xp_curve = []; }, '"xp_curve" must be'],
  ['a monster with no type', (egg, m) => { m['test-drake'].type = ''; }, 'monster "test-drake": "type" is empty'],
  ['a monster with an unknown rarity', (egg, m) => { m['test-drake'].rarity = 'mythic'; }, '"rarity" must be one of'],
  ['a sprite strip with no frame size', (egg, m) => { delete m['test-whelp'].animations.idle.frame_width; }, 'needs "frame_width" and "frame_height"'],
  ['a monster likes list too short to pick from', (egg, m) => { m['test-whelp'].traits = { likes: ['Fishing', 'Gold', 'Rain'] }; }, 'needs at least 4 entries'],
  ['shared personality chances that do not total 100', (egg, m, t) => { t.personality[0].chance += 1; }, 'personality chances add up to 101%'],
  ['a shared personality listed twice', (egg, m, t) => { t.personality[1].name = t.personality[0].name; }, 'a personality is listed twice'],
  ['a personality with no chance', (egg, m, t) => { delete t.personality[0].chance; }, 'needs a "name" and a "chance"'],
  ['a personality written as a plain word', (egg, m, t) => { t.personality[0] = 'Eager'; }, 'needs a "name" and a "chance"'],
  ['a monster personality list that does not total 100', (egg, m) => { m['test-whelp'].traits = { personality: [{ name: 'Grumpy', chance: 50 }] }; }, 'monster "test-whelp": personality chances add up to 50%'],
  ['traits.json with no likes', (egg, m, t) => { delete t.likes; }, 'needs both "personality" and "likes"'],
];
for (const [what, breakIt, fragment] of broken) {
  test(`catches ${what}`, () => expectError(check(breakIt), fragment));
}

test('catches a monster folder with no monster.json', () => {
  expectError(check(() => {}, { skipFiles: ['monsters/test-drake/monster.json'] }), 'monsters/test-drake/monster.json: missing');
});

test('catches an animation file that is not in the repo', () => {
  expectError(check(() => {}, { skipFiles: ['monsters/test-whelp/assets/idle.png'] }), 'file monsters/test-whelp/assets/idle.png not found');
});

test('catches an egg with no shop image', () => {
  expectError(check(egg => { delete egg.shop_image; }), '"shop_image" is missing');
});

test('catches a shop image file that is not in the repo', () => {
  expectError(check(() => {}, { skipFiles: ['eggs/test-egg/assets/shop.png'] }), 'shop image assets/shop.png not found');
});

for (const [width, height, why] of [[300, 300, 'square'], [600, 118, 'too wide (5:1)'], [300, 100, 'too small']]) {
  test(`catches a shop image that is ${why}`, () => {
    expectError(check(() => {}, { shopSize: [width, height] }), `shop image is ${width}×${height}`);
  });
}

test('accepts shop images from 2.5:1 to 3.5:1', () => {
  for (const size of [[400, 160], [480, 160], [560, 160], [960, 320]]) assert.deepEqual(check(() => {}, { shopSize: size }), [], size.join('×'));
});

test('accepts art borrowed from another egg or monster folder', () => {
  const errors = check((egg, m) => {
    egg.animations.idle.src = '../other-egg/assets/idle.png';
    m['test-drake'].animations.idle = { src: '../other-monster/assets/idle.png' };
  }, { extraFiles: ['eggs/other-egg/assets/idle.png', 'monsters/other-monster/assets/idle.png'] });
  assert.deepEqual(errors, []);
});

test('catches borrowed art that is not there', () => {
  expectError(check(egg => { egg.animations.idle.src = '../other-egg/assets/idle.png'; }), 'file eggs/other-egg/assets/idle.png not found');
});

test('catches art that points outside the pets folder', () => {
  expectError(check(egg => { egg.animations.idle.src = '../../../index.html'; }), 'points outside the pets folder');
});

test('accepts optional throws and a call sound', () => {
  const errors = check((egg, m) => {
    m['test-whelp'].throws = [{ emoji: '🍌' }, { src: 'assets/idle.png' }];
    m['test-whelp'].sounds = { call: { src: 'assets/idle.png', volume: 0.5 } };
  });
  assert.deepEqual(errors, []);
});

const brokenExtras = [
  ['an empty throws list', m => { m.throws = []; }, '"throws" must be a non-empty list'],
  ['a throw with both emoji and src', m => { m.throws = [{ emoji: '🍌', src: 'assets/idle.png' }]; }, 'needs exactly one of "emoji" or "src"'],
  ['a throw image that is not there', m => { m.throws = [{ src: 'assets/carrot.webp' }]; }, 'file assets/carrot.webp not found'],
  ['sounds with no call', m => { m.sounds = {}; }, '"sounds" needs a "call"'],
  ['a call sound file that is not there', m => { m.sounds = { call: { src: 'assets/call.ogg' } }; }, 'call sound assets/call.ogg not found'],
  ['a call volume above 1', m => { m.sounds = { call: { src: 'assets/idle.png', volume: 2 } }; }, '"volume" must be between 0 and 1'],
];
for (const [what, breakIt, fragment] of brokenExtras) {
  test(`catches ${what}`, () => expectError(check((egg, m) => breakIt(m['test-whelp'])), fragment));
}

test('accepts skins', () => {
  assert.deepEqual(check((egg, m) => { m['test-whelp'].skins = [{ key: 'gold', chance: 1, animations: { idle: { src: 'assets/idle.png' } } }]; }), []);
});

const brokenSkins = [
  ['skins that total 100% or more', [{ key: 'a', chance: 60, animations: { idle: { src: 'assets/idle.png' } } }, { key: 'b', chance: 40, animations: { idle: { src: 'assets/idle.png' } } }], 'skin chances add up to 100%'],
  ['a skin listed twice', [{ key: 'a', chance: 1, animations: { idle: { src: 'assets/idle.png' } } }, { key: 'a', chance: 1, animations: { idle: { src: 'assets/idle.png' } } }], 'skin "a" is listed twice'],
  ['a skin with no idle art', [{ key: 'a', chance: 1, animations: {} }], 'skin "a": needs an "idle" animation'],
  ['a skin whose art is not there', [{ key: 'a', chance: 1, animations: { idle: { src: 'assets/gold.webp' } } }], 'file monsters/test-whelp/assets/gold.webp not found'],
  ['a skin with no chance', [{ key: 'a', animations: { idle: { src: 'assets/idle.png' } } }], 'needs a "chance" above 0'],
];
for (const [what, skins, fragment] of brokenSkins) {
  test(`catches ${what}`, () => expectError(check((egg, m) => { m['test-whelp'].skins = skins; }), fragment));
}
