// Seeded generation must be repeatable, fair and independent between the monster roll and the traits.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const Pets = require('../helpers/generate-pet.js');
const traits = require('../traits.json');

const whelp = { key: 'whelp', name: 'Whelp', type: 'Dragonkin', rarity: 'common' };
const egg = { contents: [{ monster: 'whelp', chance: 70 }, { monster: 'drake', chance: 25 }, { monster: 'wyrm', chance: 5 }] };

test('the same seed always makes the same pet', () => {
  for (const seed of [1, 42, 2 ** 31, 4294967295]) {
    assert.deepEqual(Pets.generatePet(seed, whelp, traits), Pets.generatePet(seed, whelp, traits));
    assert.equal(Pets.rollMonster(seed, egg), Pets.rollMonster(seed, egg));
  }
});

test('a pet has 2 or 3 different likes and a dislike that is not one of them', () => {
  const sizes = { 2: 0, 3: 0 };
  for (let seed = 1; seed <= 2000; seed++) {
    const p = Pets.generatePet(seed, whelp, traits);
    assert.ok(p.likes.length === 2 || p.likes.length === 3, `seed ${seed}: ${p.likes.length} likes`);
    sizes[p.likes.length]++;
    assert.equal(new Set(p.likes).size, p.likes.length, `seed ${seed}: repeated like`);
    assert.equal(p.dislikes.length, 1);
    assert.ok(!p.likes.includes(p.dislikes[0]), `seed ${seed}`);
    assert.ok(traits.personality.some(t => t.name === p.personality));
  }
  for (const n of [2, 3]) assert.ok(Math.abs(sizes[n] / 2000 - 0.5) < 0.05, `${sizes[n]} of 2000 pets had ${n} likes, expected about half`);
});

test('the pet takes its name, type and rarity from the monster', () => {
  const p = Pets.generatePet(7, whelp, traits);
  assert.equal(p.monster, 'whelp');
  assert.equal(p.name, 'Whelp');
  assert.equal(p.type, 'Dragonkin');
  assert.equal(p.rarity, 'common');
});

test("a monster's own trait lists replace the shared ones", () => {
  const grump = { ...whelp, traits: { personality: [{ name: 'Grumpy', chance: 100 }], likes: ['Naps', 'Rocks', 'Rain', 'Mud'] } };
  for (let seed = 1; seed <= 200; seed++) {
    const p = Pets.generatePet(seed, grump, traits);
    assert.equal(p.personality, 'Grumpy');
    assert.ok([...p.likes, ...p.dislikes].every(x => grump.traits.likes.includes(x)));
  }
});

test('monster chances hold over 20,000 rolls, including a 5% one', () => {
  const counts = {};
  for (let seed = 1; seed <= 20000; seed++) counts[Pets.rollMonster(seed, egg)] = (counts[Pets.rollMonster(seed, egg)] || 0) + 1;
  for (const c of egg.contents) {
    const pct = counts[c.monster] / 200;
    assert.ok(Math.abs(pct - c.chance) < 1, `${c.monster}: set ${c.chance}%, rolled ${pct}%`);
  }
});

test('each personality comes up at its set chance (within 0.5 points over 50,000 pets)', () => {
  const ROLLS = 50000, counts = {};
  for (let seed = 1; seed <= ROLLS; seed++) {
    const p = Pets.generatePet(seed, whelp, traits).personality;
    counts[p] = (counts[p] || 0) + 1;
  }
  for (const { name, chance } of traits.personality) {
    const pct = 100 * (counts[name] || 0) / ROLLS;
    assert.ok(Math.abs(pct - chance) < 0.5, `${name}: set ${chance}%, rolled ${pct.toFixed(2)}%`);
  }
});

test('the monster rolled does not steer the personality', () => {
  // Pets that rolled the 5% monster should split between two halves of the personality list
  // in the same proportion as the list's chances.
  const firstHalf = new Set(traits.personality.slice(0, traits.personality.length / 2).map(p => p.name));
  const expected = traits.personality.filter(p => firstHalf.has(p.name)).reduce((sum, p) => sum + p.chance, 0) / 100;
  let rare = 0, inFirstHalf = 0;
  for (let seed = 1; seed <= 100000; seed++) {
    if (Pets.rollMonster(seed, egg) !== 'wyrm') continue;
    rare++;
    if (firstHalf.has(Pets.generatePet(seed, whelp, traits).personality)) inFirstHalf++;
  }
  assert.ok(Math.abs(inFirstHalf / rare - expected) < 0.03, `${inFirstHalf} of ${rare}, expected about ${(expected * 100).toFixed(0)}%`);
});

test('levels follow the XP curve, with XP past the cap banked', () => {
  const curve = [60, 100, 140, 180, 230, 290];
  const cases = [[0, 1], [59, 1], [60, 2], [159, 2], [160, 3], [999, 6], [1000, 7], [99999, 7]];
  for (const [xp, level] of cases) assert.equal(Pets.levelForXp(xp, curve), level, `${xp} XP`);
});

test('xp.json gives positive whole XP, with a win worth at least a loss', () => {
  const xp = require('../xp.json');
  for (const k of ['minigame_win', 'minigame_loss']) assert.ok(Number.isInteger(xp[k]) && xp[k] > 0, `${k}: ${xp[k]}`);
  assert.ok(xp.minigame_win >= xp.minigame_loss);
});

test('the default curve takes 77 games of wins, 112 at half wins, or 200 of losses to reach level 7', () => {
  const curve = [60, 100, 140, 180, 230, 290];
  const xp = require('../xp.json');
  const gamesToCap = perGame => { let games = 0, total = 0; while (Pets.levelForXp(total, curve) < 7) { total += perGame(games++); } return games; };
  assert.equal(gamesToCap(() => xp.minigame_win), 77);
  assert.equal(gamesToCap(() => (xp.minigame_win + xp.minigame_loss) / 2), 112); // average XP at a 50% win rate
  assert.equal(gamesToCap(() => xp.minigame_loss), 200);
});
