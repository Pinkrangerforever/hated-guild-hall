// The mock backend applies the rules the real RPCs must follow, so these tests are their spec too.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { createPetApi, START_GOLD, NICKNAME_MAX } = require('../helpers/pet-api-mock.js');

const catalog = {
  eggs: {
    'test-egg': {
      key: 'test-egg', name: 'Test Egg', description: 'x', price: 500, shop_image: 'assets/shop.webp',
      hatch: { actions: ['visit_calendar', 'visit_roster', 'open_shop'], distinct_actions: 2 },
      contents: [{ monster: 'whelp', chance: 50 }, { monster: 'drake', chance: 50 }],
      xp_curve: [60, 100],
    },
  },
  monsters: {
    whelp: { key: 'whelp', name: 'Whelp', type: 'Dragonkin', rarity: 'common' },
    drake: { key: 'drake', name: 'Drake', type: 'Dragonkin', rarity: 'rare' },
  },
  traits: require('../traits.json'),
  actions: require('../hatch-actions.json'),
  xp: { minigame_win: 13, minigame_loss: 5 },
  items: [{ id: 'flame', name: 'Flame', description: 'x', cost: 300, category: 'name_customization', image_url: 'flame-bg.webp' }],
};

function hatched(api = createPetApi(catalog)) {
  const { purchase } = api.purchaseShopItem('test-egg');
  api.recordSiteAction('visit_calendar');
  api.recordSiteAction('visit_roster');
  return { api, pet: api.hatchPet(purchase.id) };
}

test('buying an egg costs its price and starts an empty checklist', () => {
  const api = createPetApi(catalog);
  const { gold, purchase } = api.purchaseShopItem('test-egg');
  assert.equal(gold, START_GOLD - 500);
  assert.deepEqual([purchase.done, purchase.total, purchase.ready], [0, 2, false]);
});

test("can't buy without enough gold, or a second copy while one is unhatched", () => {
  const api = createPetApi(catalog);
  api.purchaseShopItem('test-egg');
  assert.throws(() => api.purchaseShopItem('test-egg'), /already have an unhatched/);
  const poor = createPetApi(catalog);
  poor.dev.addGold(-START_GOLD);
  assert.throws(() => poor.purchaseShopItem('test-egg'), /Not enough gold/);
  assert.throws(() => poor.purchaseShopItem('nope'), /not in the Shop/);
});

test('only distinct, listed actions count, and only after the egg was bought', () => {
  const api = createPetApi(catalog);
  api.recordSiteAction('visit_calendar'); // before buying: doesn't count toward the egg
  const { purchase } = api.purchaseShopItem('test-egg');
  assert.equal(api.recordSiteAction('visit_loot').advanced, null); // not on this egg's list
  assert.equal(api.recordSiteAction('visit_roster').advanced.done, 1);
  assert.equal(api.recordSiteAction('visit_roster').advanced, null); // repeat
  const last = api.recordSiteAction('visit_calendar').advanced;
  assert.deepEqual([last.purchaseId, last.done, last.ready], [purchase.id, 2, true]);
  assert.throws(() => api.recordSiteAction('made_up'), /Unknown action/);
});

test("an egg can't hatch until ready, and only once", () => {
  const api = createPetApi(catalog);
  const { purchase } = api.purchaseShopItem('test-egg');
  api.recordSiteAction('visit_calendar');
  assert.throws(() => api.hatchPet(purchase.id), /Not ready yet: 1 \/ 2/);
  api.recordSiteAction('open_shop');
  api.hatchPet(purchase.id);
  assert.throws(() => api.hatchPet(purchase.id), /already hatched/);
  assert.throws(() => api.hatchPet('purchase-999'), /not yours/);
});

test('a hatched pet comes from the egg contents, starts at level 1 and becomes active', () => {
  const { api, pet } = hatched();
  assert.ok(['whelp', 'drake'].includes(pet.monsterKey));
  assert.equal(pet.nickname, catalog.monsters[pet.monsterKey].name);
  assert.deepEqual([pet.level, pet.totalXp, pet.active], [1, 0, true]);
  assert.equal(api.getState().eggs.length, 0);
  assert.equal(api.getState().pets.length, 1);
});

test('the hatch roll follows the egg chances', () => {
  const counts = { whelp: 0, drake: 0 };
  for (let i = 0; i < 2000; i++) counts[hatched().pet.monsterKey]++;
  assert.ok(Math.abs(counts.whelp / 2000 - 0.5) < 0.05, JSON.stringify(counts));
});

test('minigames pay 13 XP for a win and 5 for a loss to the active pet, and level it up', () => {
  const { api } = hatched();
  assert.equal(api.awardPetXp(true).awarded, 13);
  assert.equal(api.awardPetXp(false).awarded, 5);
  let result;
  for (let i = 0; i < 4; i++) result = api.awardPetXp(true); // 18 + 52 = 70 XP, past the 60 for level 2
  assert.equal(result.pet.totalXp, 70);
  assert.equal(result.pet.level, 2);
  assert.ok(Math.abs(result.pet.levelProgress - 0.1) < 1e-9);
  assert.deepEqual([result.pet.levelXp, result.pet.levelXpNeeded], [10, 100]); // shown as "10 / 100 XP" on hover
});

test('XP goes only to the active pet, and nowhere without one', () => {
  assert.deepEqual(createPetApi(catalog).awardPetXp(true), { awarded: 0, pet: null, reason: 'none' });
  const { api, pet: first } = hatched();
  api.dev.addGold(1000);
  api.setPrefs({ autoActivate: true });
  const { purchase } = api.purchaseShopItem('test-egg');
  assert.deepEqual(api.awardPetXp(true), { awarded: 0, pet: null, reason: 'egg' }); // an active egg earns no XP
  api.recordSiteAction('visit_calendar');
  api.recordSiteAction('visit_roster');
  const second = api.hatchPet(purchase.id);
  api.awardPetXp(true);
  api.setActive(first.id);
  api.awardPetXp(false);
  const pets = Object.fromEntries(api.getState().pets.map(p => [p.id, p.totalXp]));
  assert.deepEqual(pets, { [first.id]: 5, [second.id]: 13 });
});

test('at the hidden cap the bar stays full and XP keeps banking', () => {
  const { api } = hatched();
  let result;
  for (let i = 0; i < 20; i++) result = api.awardPetXp(true); // 260 XP, cap at 160
  assert.deepEqual([result.pet.level, result.pet.totalXp, result.pet.levelProgress], [3, 260, 1]);
  assert.equal(result.pet.levelXpNeeded, null); // no next level to show
});

test('nicknames are trimmed and limited to 24 characters', () => {
  const { api, pet } = hatched();
  assert.equal(api.renamePet(pet.id, '  Sir   Bananas ').nickname, 'Sir Bananas');
  assert.throws(() => api.renamePet(pet.id, '   '), /at least one character/);
  assert.throws(() => api.renamePet(pet.id, 'x'.repeat(NICKNAME_MAX + 1)), /at most 24/);
  assert.throws(() => api.renamePet('pet-999', 'Bob'), /not yours/);
});

test('state survives a reload through storage', () => {
  const store = {};
  const storage = { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = v; } };
  const { pet } = hatched(createPetApi(catalog, { storage }));
  const reloaded = createPetApi(catalog, { storage });
  assert.equal(reloaded.getState().pets[0].id, pet.id);
  reloaded.dev.reset();
  assert.equal(createPetApi(catalog, { storage }).getState().pets.length, 0);
});

test('ordinary Shop items are bought once, kept, and listed with the Shop', () => {
  const api = createPetApi(catalog);
  assert.deepEqual(api.getShopItems().map(i => [i.id, i.owned]), [['test-egg', false], ['flame', false]]);
  const { gold, item } = api.purchaseShopItem('flame');
  assert.equal(gold, START_GOLD - 300);
  assert.equal(item.name, 'Flame');
  assert.throws(() => api.purchaseShopItem('flame'), /already own Flame/);
  assert.equal(api.getShopItems().find(i => i.id === 'flame').owned, true);
  assert.deepEqual(api.getState().items.map(i => i.itemId), ['flame']);
});

test('an egg can be bought again once the last one has hatched', () => {
  const { api } = hatched();
  assert.equal(api.getShopItems().find(i => i.id === 'test-egg').owned, false);
  api.purchaseShopItem('test-egg');
  assert.equal(api.getState().eggs.length, 1);
});

test('state saved before items existed still loads', () => {
  const store = { 'pets-mock-state': JSON.stringify({ gold: 50, purchases: [], pets: [], activePetId: 'pet-7', actions: {}, nextId: 1 }) };
  const storage = { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = v; } };
  const api = createPetApi(catalog, { storage });
  assert.deepEqual(api.getState().items, []);
  assert.equal(api.getState().gold, 50);
  assert.equal(api.getState().activeId, 'pet-7'); // the old activePetId carries over
  assert.deepEqual(api.getState().prefs, { corner: 'bottom-right', visible: true, autoActivate: false, setupDone: false, sounds: true, eggShopFound: false });
});

/* ---------- the active companion (pets/FLOW.md) ---------- */

test('a first egg becomes active by itself and asks for first-time setup', () => {
  const api = createPetApi(catalog);
  const r = api.purchaseShopItem('test-egg');
  assert.deepEqual([r.becameActive, r.askToActivate, r.needsSetup], [true, false, true]);
  assert.deepEqual([api.getState().activeId, api.getState().activeKind], [r.purchase.id, 'egg']);
  api.setPrefs({ setupDone: true });
  api.dev.addGold(1000);
  api.recordSiteAction('visit_calendar');
  api.recordSiteAction('visit_roster');
  api.hatchPet(r.purchase.id);
  assert.equal(api.purchaseShopItem('test-egg').needsSetup, false);
});

test('a new egg asks to become active when another companion is, unless "always" is on', () => {
  const { api, pet } = hatched();
  api.dev.addGold(1000);
  const asked = api.purchaseShopItem('test-egg');
  assert.deepEqual([asked.becameActive, asked.askToActivate], [false, true]);
  assert.equal(api.getState().activeId, pet.id);
  api.setActive(asked.purchase.id);
  assert.equal(api.getState().activeKind, 'egg');

  const { api: auto } = hatched();
  auto.setPrefs({ autoActivate: true });
  const r = auto.purchaseShopItem('test-egg');
  assert.deepEqual([r.becameActive, r.askToActivate], [true, false]);
  assert.equal(auto.getState().activeId, r.purchase.id);
});

test("an inactive egg doesn't tick off actions and can't hatch", () => {
  const { api, pet } = hatched();
  api.dev.addGold(1000);
  const { purchase } = api.purchaseShopItem('test-egg'); // stays inactive: the pet is active
  assert.equal(api.recordSiteAction('open_shop').advanced, null);
  assert.equal(api.getState().eggs[0].done, 0);
  api.setActive(purchase.id);
  api.recordSiteAction('open_shop');
  api.recordSiteAction('visit_roster');
  api.setActive(pet.id);
  assert.throws(() => api.hatchPet(purchase.id), /Only your active companion can hatch/);
});

test("a hatched pet always takes over the egg's active slot", () => {
  const { api } = hatched();
  api.dev.addGold(1000);
  api.setPrefs({ autoActivate: true });
  const { purchase } = api.purchaseShopItem('test-egg');
  api.recordSiteAction('visit_calendar');
  api.recordSiteAction('visit_roster');
  const second = api.hatchPet(purchase.id);
  assert.equal(second.active, true);
  assert.deepEqual([api.getState().activeId, api.getState().activeKind], [second.id, 'pet']);
});

test('only your own eggs and pets can be made active', () => {
  const { api, pet } = hatched();
  assert.throws(() => api.setActive('pet-999'), /not yours/);
  assert.throws(() => api.setActive(pet.purchaseId), /not yours/); // a hatched egg is gone
});

test('companion settings are validated', () => {
  const api = createPetApi(catalog);
  assert.deepEqual(api.setPrefs({ corner: 'top-left', visible: false }), { corner: 'top-left', visible: false, autoActivate: false, setupDone: false, sounds: true, eggShopFound: false });
  assert.throws(() => api.setPrefs({ corner: 'middle' }), /Corner must be one of/);
  assert.throws(() => api.setPrefs({ visible: 'no' }), /"visible" must be true or false/);
  assert.equal(api.setPrefs({ sounds: false }).sounds, false); // Pet sounds can be turned off
  assert.equal(api.getState().prefs.corner, 'top-left'); // a refused change leaves the old settings
});

/* ---------- skins (pets/FLOW.md §9) ---------- */

test('a hatch rolls a skin from the monster: about 1% get it, the rest the normal art', () => {
  const skinned = { ...catalog, monsters: Object.fromEntries(Object.entries(catalog.monsters).map(([k, m]) => [k, { ...m, skins: [{ key: 'gold', chance: 1, animations: { idle: { src: 'x' } } }] }])) };
  let gold = 0;
  for (let i = 0; i < 20000; i++) if (hatched(createPetApi(skinned)).pet.skin === 'gold') gold++;
  assert.ok(Math.abs(gold / 20000 - 0.01) < 0.004, `${gold} of 20000`);
});

test('a monster without skins always hatches with the normal art', () => {
  for (let i = 0; i < 200; i++) assert.equal(hatched().pet.skin, null);
});

test('the sandbox can force a skin on the next hatch only', () => {
  const api = createPetApi(catalog);
  api.dev.forceSkin('gold');
  assert.equal(hatched(api).pet.skin, 'gold');
  api.dev.addGold(1000);
  api.setPrefs({ autoActivate: true }); // so the second egg is active and can hatch
  assert.equal(hatched(api).pet.skin, null);
});
