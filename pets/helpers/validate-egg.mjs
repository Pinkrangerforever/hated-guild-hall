// Checks an egg and the monsters it hatches, then optionally writes its shop SQL.
//   node pets/helpers/validate-egg.mjs <egg-key>          check files, print roll odds
//   node pets/helpers/validate-egg.mjs <egg-key> --sql    also write pets/eggs/<key>/shop_item.sql
// The test suite (node --test pets/tests/) imports validateEgg and shopSql from here.
import { readFileSync, writeFileSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve, relative, isAbsolute, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

export const PETS = join(dirname(fileURLToPath(import.meta.url)), '..');
const Pets = createRequire(import.meta.url)('./generate-pet.js');

const RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
const KEY_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const BIG_ASSET_BYTES = 500 * 1024; // the overlay sits on every page, so keep its art light
const BIG_SOUND_BYTES = 100 * 1024;
// Shop cards show their image 80px tall and 150–260px wide, cropped to fill (object-fit: cover).
export const SHOP_IMAGE = { minWidth: 360, minRatio: 2.5, maxRatio: 3.5 };

// Width and height from a PNG, GIF or WebP header, or null for other formats.
export function imageSize(file) {
  const b = readFileSync(file);
  if (b.length >= 24 && b.toString('latin1', 1, 4) === 'PNG') return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
  if (b.length >= 10 && b.toString('latin1', 0, 3) === 'GIF') return { width: b.readUInt16LE(6), height: b.readUInt16LE(8) };
  if (b.length >= 30 && b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP') {
    const chunk = b.toString('latin1', 12, 16);
    if (chunk === 'VP8X') return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
    if (chunk === 'VP8 ') return { width: b.readUInt16LE(26) & 0x3FFF, height: b.readUInt16LE(28) & 0x3FFF };
    if (chunk === 'VP8L') {
      const bits = b.readUInt32LE(21);
      return { width: 1 + (bits & 0x3FFF), height: 1 + ((bits >>> 14) & 0x3FFF) };
    }
  }
  return null;
}

// Returns { egg, monsters, errors, warnings }. `root` is the pets folder; tests pass a temp copy.
export function validateEgg(key, root = PETS) {
  const errors = [], warnings = [];
  const fail = msg => errors.push(msg);
  const warn = msg => warnings.push(msg);
  const rel = path => path.slice(root.length + 1).replace(/\\/g, '/');

  function readJson(path) {
    try { return JSON.parse(readFileSync(path, 'utf8')); }
    catch (e) { fail(`${rel(path)}: ${existsSync(path) ? 'invalid JSON (' + e.message + ')' : 'missing'}`); return null; }
  }

  function checkAnimations(owner, folder, animations, required) {
    if (!animations || typeof animations !== 'object') return fail(`${owner}: "animations" is missing`);
    for (const name of required) if (!animations[name]) fail(`${owner}: needs an "${name}" animation`);
    for (const [name, anim] of Object.entries(animations)) {
      const where = `${owner} animation "${name}"`;
      if (!anim.src) { fail(`${where}: no "src"`); continue; }
      const file = join(folder, anim.src);
      const fromRoot = relative(root, file);
      if (fromRoot.startsWith('..') || isAbsolute(fromRoot)) { fail(`${where}: "${anim.src}" points outside the pets folder`); continue; }
      if (!existsSync(file)) { fail(`${where}: file ${rel(file)} not found`); continue; }
      if (statSync(file).size > BIG_ASSET_BYTES) warn(`${where}: ${rel(file)} is ${Math.round(statSync(file).size / 1024)} KB, over 500 KB`);
      const frames = anim.frames ?? 1;
      if (!Number.isInteger(frames) || frames < 1) fail(`${where}: "frames" must be a whole number of at least 1`);
      if (frames > 1 && !(anim.frame_width > 0 && anim.frame_height > 0)) fail(`${where}: a sprite strip needs "frame_width" and "frame_height"`);
      if (frames > 1 && /\.gif$/i.test(anim.src)) warn(`${where}: a GIF already animates itself, so "frames" should be 1`);
    }
  }

  // Shared traits.json, or a monster's own "traits"; either list may be left out of a monster.
  function checkTraits(owner, pools) {
    if (pools.personality !== undefined) {
      const list = pools.personality;
      if (!Array.isArray(list) || !list.length) fail(`${owner}: "personality" must be a non-empty list`);
      else {
        if (list.some(p => !p?.name || !(p.chance > 0))) fail(`${owner}: each personality needs a "name" and a "chance" above 0`);
        const total = list.reduce((sum, p) => sum + (p?.chance || 0), 0);
        if (Math.abs(total - 100) > 1e-9) fail(`${owner}: personality chances add up to ${total}%, not 100%`);
        const names = list.map(p => p?.name);
        if (new Set(names).size !== names.length) fail(`${owner}: a personality is listed twice`);
      }
    }
    if (pools.likes !== undefined) {
      if (!Array.isArray(pools.likes) || pools.likes.length < 4) fail(`${owner}: "likes" needs at least 4 entries (up to 3 likes + 1 dislike)`);
      else if (new Set(pools.likes).size !== pools.likes.length) fail(`${owner}: a like is listed twice`);
    }
  }

  // Optional: the easter egg's throws (pets/FLOW.md §8) and the monster's call (§7).
  function checkExtras(owner, folder, m) {
    const inside = file => { const r = relative(root, file); return !r.startsWith('..') && !isAbsolute(r); };
    if (m.throws !== undefined) {
      if (!Array.isArray(m.throws) || !m.throws.length) fail(`${owner}: "throws" must be a non-empty list`);
      else m.throws.forEach((t, i) => {
        const where = `${owner} throws[${i}]`;
        if (!!t?.emoji === !!t?.src) return fail(`${where}: needs exactly one of "emoji" or "src"`);
        if (t.src && (!inside(join(folder, t.src)) || !existsSync(join(folder, t.src)))) fail(`${where}: file ${t.src} not found`);
      });
    }
    const c = m.sounds?.call;
    if (m.sounds !== undefined && !c) fail(`${owner}: "sounds" needs a "call"`);
    if (c) {
      const file = join(folder, c.src || '');
      if (!c.src || !inside(file) || !existsSync(file)) fail(`${owner}: call sound ${c.src || '(no src)'} not found`);
      else if (statSync(file).size > BIG_SOUND_BYTES) fail(`${owner}: call sound is ${Math.round(statSync(file).size / 1024)} KB; keep it under 100 KB`);
      if (c.volume !== undefined && !(c.volume > 0 && c.volume <= 1)) fail(`${owner}: call "volume" must be between 0 and 1`);
    }
  }

  // Optional alternate art (pets/FLOW.md §9).
  function checkSkins(owner, folder, skins) {
    if (skins === undefined) return;
    if (!Array.isArray(skins) || !skins.length) return fail(`${owner}: "skins" must be a non-empty list`);
    const keys = new Set();
    let total = 0;
    for (const s of skins) {
      const where = `${owner} skin "${s?.key}"`;
      if (!KEY_RE.test(s?.key || '')) fail(`${owner}: each skin needs a lowercase-with-dashes "key"`);
      if (keys.has(s?.key)) fail(`${owner}: skin "${s.key}" is listed twice`);
      keys.add(s?.key);
      if (!(s?.chance > 0)) fail(`${where}: needs a "chance" above 0`);
      total += s?.chance || 0;
      checkAnimations(where, folder, s?.animations, ['idle']);
    }
    if (total >= 100) fail(`${owner}: skin chances add up to ${total}%; they must stay under 100% so the normal art can still roll`);
  }

  function checkMonster(mkey) {
    const folder = join(root, 'monsters', mkey);
    const m = readJson(join(folder, 'monster.json'));
    if (!m) return null;
    const owner = `monster "${mkey}"`;
    if (m.key !== mkey) fail(`${owner}: "key" is "${m.key}" but the folder is "${mkey}"`);
    for (const field of ['name', 'type', 'description']) if (!m[field]) fail(`${owner}: "${field}" is empty`);
    if (!RARITIES.includes(m.rarity)) fail(`${owner}: "rarity" must be one of ${RARITIES.join(', ')}`);
    checkAnimations(owner, folder, m.animations, ['idle']);
    checkTraits(owner, m.traits || {});
    checkExtras(owner, folder, m);
    checkSkins(owner, folder, m.skins);
    return m;
  }

  const folder = join(root, 'eggs', key);
  const egg = readJson(join(folder, 'egg.json'));
  const monsters = {};
  if (!egg) return { egg, monsters, errors, warnings };
  const owner = `egg "${key}"`;
  const actions = readJson(join(root, 'hatch-actions.json')) || {};
  const traits = readJson(join(root, 'traits.json'));
  if (traits) {
    if (!traits.personality || !traits.likes) fail('traits.json: needs both "personality" and "likes"');
    checkTraits('traits.json', traits);
  }

  if (!KEY_RE.test(key)) fail(`${owner}: folder name must be lowercase-with-dashes`);
  if (egg.key !== key) fail(`${owner}: "key" is "${egg.key}" but the folder is "${key}"`);
  for (const field of ['name', 'description']) if (!egg[field]) fail(`${owner}: "${field}" is empty`);
  if (!Number.isInteger(egg.price) || egg.price <= 0) fail(`${owner}: "price" must be a positive whole number of gold`);
  if (!egg.shop_image) fail(`${owner}: "shop_image" is missing. Run: python pets/helpers/make-shop-art.py ${key}`);
  else if (!existsSync(join(folder, egg.shop_image))) fail(`${owner}: shop image ${egg.shop_image} not found`);
  else {
    const size = imageSize(join(folder, egg.shop_image));
    if (!size) warn(`${owner}: can't read the size of ${egg.shop_image}; use PNG, GIF or WebP`);
    else {
      const ratio = size.width / size.height;
      if (ratio < SHOP_IMAGE.minRatio || ratio > SHOP_IMAGE.maxRatio || size.width < SHOP_IMAGE.minWidth) {
        fail(`${owner}: shop image is ${size.width}×${size.height}; it needs to be about 3:1 and at least ${SHOP_IMAGE.minWidth}px wide (480×160 is ideal)`);
      }
    }
  }
  checkAnimations(owner, folder, egg.animations, ['idle']);

  const hatch = egg.hatch || {};
  const pool = hatch.actions || [];
  for (const a of pool) if (!actions[a]) fail(`${owner}: hatch action "${a}" is not in hatch-actions.json`);
  if (new Set(pool).size !== pool.length) fail(`${owner}: "hatch.actions" lists an action twice`);
  if (!Number.isInteger(hatch.distinct_actions) || hatch.distinct_actions < 1 || hatch.distinct_actions > pool.length) {
    fail(`${owner}: "hatch.distinct_actions" must be between 1 and the ${pool.length} listed actions`);
  }

  const contents = egg.contents || [];
  if (!contents.length) fail(`${owner}: "contents" lists no monsters`);
  const total = contents.reduce((sum, c) => sum + (c.chance || 0), 0);
  if (Math.abs(total - 100) > 1e-9) fail(`${owner}: content chances add up to ${total}%, not 100%`);
  const seen = new Set();
  for (const c of contents) {
    if (!(c.chance > 0)) fail(`${owner}: monster "${c.monster}" needs a chance above 0`);
    if (seen.has(c.monster)) fail(`${owner}: monster "${c.monster}" is listed twice`);
    seen.add(c.monster);
    const m = checkMonster(c.monster);
    if (m) monsters[c.monster] = m;
  }

  const curve = egg.xp_curve || [];
  if (!curve.length || !curve.every(n => Number.isInteger(n) && n > 0)) fail(`${owner}: "xp_curve" must be a list of positive whole numbers`);
  else if (curve.some((n, i) => i && n < curve[i - 1])) warn(`${owner}: "xp_curve" goes down at some level; each level usually costs more`);

  return { egg, monsters, errors, warnings };
}

export function rollOdds(egg, rolls = 10000) {
  const counts = {};
  for (let seed = 1; seed <= rolls; seed++) {
    const m = Pets.rollMonster(seed, egg);
    counts[m] = (counts[m] || 0) + 1;
  }
  return Object.fromEntries(egg.contents.map(c => [c.monster, 100 * (counts[c.monster] || 0) / rolls]));
}

// monsters: the egg's monster.json files by key; their skin chances go into the metadata for hatch_pet.
export function shopSql(egg, monsters = {}) {
  const sqlText = s => `'${String(s).replace(/'/g, "''")}'`;
  const metadata = {
    egg: egg.key,
    gen_version: Pets.GEN_VERSION,
    hatch: egg.hatch,
    contents: egg.contents.map(({ monster, chance }) => ({ monster, chance })),
    xp_curve: egg.xp_curve,
  };
  const skins = Object.fromEntries(egg.contents
    .filter(c => monsters[c.monster]?.skins)
    .map(c => [c.monster, monsters[c.monster].skins.map(({ key, chance }) => ({ key, chance }))]));
  if (Object.keys(skins).length) metadata.skins = skins;
  // posix.normalize turns a borrowed "../other-egg/assets/shop.webp" into a clean site path.
  const image = posix.normalize(`pets/eggs/${egg.key}/${egg.shop_image}`);
  return `-- Generated by: node pets/helpers/validate-egg.mjs ${egg.key} --sql
-- Needs someone with Supabase access to run it. hatch_pet reads "contents" from this row to roll the monster.
INSERT INTO shop_items (name, description, cost, category, metadata, image_url, active)
VALUES (${sqlText(egg.name)}, ${sqlText(egg.description)}, ${egg.price}, 'pet_egg', ${sqlText(JSON.stringify(metadata))}, ${sqlText(image)}, true);
`;
}

function main() {
  const [key, flag] = process.argv.slice(2);
  if (!key) {
    console.error('Usage: node pets/helpers/validate-egg.mjs <egg-key> [--sql]');
    process.exit(2);
  }
  const { egg, monsters, errors, warnings } = validateEgg(key);
  for (const w of warnings) console.log('warning: ' + w);
  if (errors.length) {
    for (const e of errors) console.log('error:   ' + e);
    console.log(`\n${errors.length} error(s). Fix them and run this again.`);
    process.exit(1);
  }
  const odds = rollOdds(egg);
  const lines = egg.contents.map(c =>
    `  ${c.monster.padEnd(24)} set ${String(c.chance).padStart(5)}%   rolled ${odds[c.monster].toFixed(1).padStart(5)}%`);
  console.log(`Egg "${egg.name}" is valid.\n\nMonster odds over 10,000 test rolls:\n${lines.join('\n')}`);
  if (flag === '--sql') {
    writeFileSync(join(PETS, 'eggs', key, 'shop_item.sql'), shopSql(egg, monsters));
    console.log(`\nWrote pets/eggs/${key}/shop_item.sql`);
  }
}

if (resolve(process.argv[1] || '') === fileURLToPath(import.meta.url)) main();
