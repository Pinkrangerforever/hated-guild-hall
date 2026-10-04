/* Pet generation helpers: pure functions, no DOM, no network.
   Loaded as a classic script (window.Pets) by index.html and pets/preview.html,
   and with require() by pets/helpers/validate-egg.mjs. */
(function (root) {
  // Bump when trait picking changes, and keep the old logic for pets stored with the old version.
  const GEN_VERSION = 1;

  // murmur3 finalizer: spreads nearby seeds (1, 2, 3…) far apart before they reach the generator.
  function hashSeed(seed) {
    let h = seed >>> 0;
    h = Math.imul(h ^ (h >>> 16), 0x85EBCA6B);
    h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
    return (h ^ (h >>> 16)) >>> 0;
  }

  function mulberry32(seed) {
    let a = hashSeed(seed);
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function pickWeighted(rand, entries, weightOf) {
    const total = entries.reduce((sum, e) => sum + weightOf(e), 0);
    let r = rand() * total;
    for (const e of entries) {
      r -= weightOf(e);
      if (r < 0) return e;
    }
    return entries[entries.length - 1];
  }

  function pickDistinct(rand, pool, count, exclude = []) {
    const left = pool.filter(x => !exclude.includes(x));
    const out = [];
    while (out.length < count && left.length) out.push(left.splice(Math.floor(rand() * left.length), 1)[0]);
    return out;
  }

  // Which monster an egg hatches into. The live roll happens server-side in hatch_pet,
  // which stores monster_key on the pet; this copy is for the preview page and validator.
  // Uses its own stream (seed ^ salt) so the monster picked doesn't steer the traits.
  function rollMonster(seed, egg) {
    return pickWeighted(mulberry32(seed ^ 0x5EED5EED), egg.contents, c => c.chance).monster;
  }

  // Which skin a new pet gets: a key from monster.skins, or null for the normal art.
  // Chances are percentages; whatever's left over is the normal art. rand: a 0-1 random function.
  function rollSkin(monster, rand) {
    const skins = monster.skins || [];
    const used = skins.reduce((sum, s) => sum + s.chance, 0);
    const pick = pickWeighted(rand, [...skins, { key: null, chance: 100 - used }], s => s.chance);
    return pick.key;
  }

  // The animations to draw for a pet: its skin's, or the monster's own.
  function petAnimations(monster, skinKey) {
    const skin = skinKey && (monster.skins || []).find(s => s.key === skinKey);
    return skin ? skin.animations : monster.animations;
  }

  // Cosmetic traits for a hatched pet, worked out from its stored seed.
  // A monster's own trait lists replace the shared ones in pets/traits.json.
  // personality is [{ name, chance }] with chances totalling 100; likes is a plain list,
  // from which a pet gets 2 or 3 likes (even odds) and 1 dislike.
  function generatePet(seed, monster, traits) {
    const rand = mulberry32(seed);
    const pools = { ...traits, ...(monster.traits || {}) };
    const personality = pickWeighted(rand, pools.personality, p => p.chance).name;
    const likes = pickDistinct(rand, pools.likes, rand() < 0.5 ? 2 : 3);
    return {
      gen_version: GEN_VERSION,
      seed,
      monster: monster.key,
      name: monster.name,
      type: monster.type,
      rarity: monster.rarity,
      personality,
      likes,
      dislikes: pickDistinct(rand, pools.likes, 1, likes),
    };
  }

  // curve[i] = XP needed to go from level i+1 to i+2. XP past the last step is banked.
  function levelForXp(totalXp, curve) {
    let level = 1, needed = 0;
    for (const step of curve) {
      needed += step;
      if (totalXp < needed) break;
      level++;
    }
    return level;
  }

  const api = { GEN_VERSION, hashSeed, mulberry32, pickWeighted, pickDistinct, rollMonster, rollSkin, petAnimations, generatePet, levelForXp };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Pets = api;
})(typeof window !== 'undefined' ? window : globalThis);
