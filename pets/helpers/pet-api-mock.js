/* In-memory stand-in for the pet backend, for the sandbox page and tests.
   Each method mirrors a planned Supabase RPC and applies the same rules the server will,
   so this file is also the spec for those RPCs (see pets/FLOW.md for the member-facing flow):

     purchaseShopItem(itemId)       purchase_shop_item (exists today; generic by item)
     recordSiteAction(actionKey)    record_site_action
     hatchPet(purchaseId)           hatch_pet
     awardPetXp(won)                award_pet_xp (the real one takes the sparkle event's pending id)
     setActive(id)                  set_active_companion (an unhatched egg's purchase id, or a pet id)
     renamePet(petId, nickname)     rename_pet
     setPrefs(prefs)                an update of the member's own profiles.pet_prefs

   The active companion is one egg or one pet. Only it makes progress: an egg ticks off hatch
   actions and can hatch only while active, and a pet earns minigame XP only while active.

   Methods throw an Error with a member-facing message when a rule says no.
   Loaded as a classic script (window.PetApiMock) or with require() in tests. */
(function (root) {
  const Pets = root.Pets || (typeof require !== 'undefined' ? require('./generate-pet.js') : null);
  const NICKNAME_MAX = 24;
  const START_GOLD = 2000;
  const CORNERS = ['bottom-right', 'bottom-left', 'top-right', 'top-left'];
  const DEFAULT_PREFS = { corner: 'bottom-right', visible: true, autoActivate: false, setupDone: false, sounds: true, eggShopFound: false };

  // catalog: { eggs: {key: egg.json}, monsters: {key: monster.json}, actions: hatch-actions.json, xp: xp.json,
  //            items?: [{ id, name, description, cost, category, image_url }] } (other Shop items, for the sandbox)
  // storage: anything with getItem/setItem (localStorage in the browser), or null to keep state in memory only.
  function createPetApi(catalog, { storage = null, storageKey = 'pets-mock-state', random = Math.random } = {}) {
    let state = migrate({ ...fresh(), ...(load() || {}) });
    let forcedSkin;
    const otherItems = catalog.items || [];

    function fresh() {
      return { gold: START_GOLD, purchases: [], items: [], pets: [], activeId: null,
        prefs: { ...DEFAULT_PREFS }, actions: {}, nextId: 1, awarded: 0 };
    }
    // Sandbox state saved by older versions of this file.
    function migrate(s) {
      if (s.activePetId && !s.activeId) s.activeId = s.activePetId;
      delete s.activePetId;
      s.prefs = { ...DEFAULT_PREFS, ...(s.prefs || {}) };
      return s;
    }
    function load() {
      try { return storage && JSON.parse(storage.getItem(storageKey)); } catch (e) { return null; }
    }
    function save() {
      try { if (storage) storage.setItem(storageKey, JSON.stringify(state)); } catch (e) { /* state still works in memory */ }
    }
    const nextId = prefix => `${prefix}-${state.nextId++}`;
    const fail = message => { throw new Error(message); };
    const clone = value => JSON.parse(JSON.stringify(value));
    const findEgg = id => state.purchases.find(p => p.id === id && p.eggKey && !p.petId);
    const findPet = id => state.pets.find(p => p.id === id);

    // Progress counts actions done while the egg was active, so a new egg always starts a fresh checklist.
    function progress(purchase) {
      const egg = catalog.eggs[purchase.eggKey];
      const done = egg.hatch.actions.filter(a => purchase.actionsDone.includes(a));
      return { done: done.length, total: egg.hatch.distinct_actions, ready: done.length >= egg.hatch.distinct_actions, doneKeys: done };
    }
    const eggView = p => ({ ...clone(p), ...progress(p), active: p.id === state.activeId });

    function petView(pet) {
      const egg = catalog.eggs[pet.eggKey];
      const monster = catalog.monsters[pet.monsterKey];
      const traits = Pets.generatePet(pet.seed, monster, catalog.traits);
      const level = Pets.levelForXp(pet.totalXp, egg.xp_curve);
      let floor = 0;
      for (let i = 0; i < level - 1 && i < egg.xp_curve.length; i++) floor += egg.xp_curve[i];
      const step = egg.xp_curve[level - 1];
      return {
        ...clone(pet), ...traits, nickname: pet.nickname, level,
        // Progress toward the next level. At the hidden cap the bar stays full and levelXpNeeded is null.
        levelProgress: step ? (pet.totalXp - floor) / step : 1,
        levelXp: pet.totalXp - floor,
        levelXpNeeded: step || null,
        active: pet.id === state.activeId,
      };
    }

    return {
      getState() {
        return {
          gold: state.gold,
          activeId: state.activeId,
          activeKind: findPet(state.activeId) ? 'pet' : findEgg(state.activeId) ? 'egg' : null,
          prefs: clone(state.prefs),
          actions: Object.keys(state.actions),
          eggs: state.purchases.filter(p => p.eggKey && !p.petId).map(eggView),
          items: state.items.map(owned => ({ ...clone(owned), ...clone(otherItems.find(i => i.id === owned.itemId)) })),
          pets: state.pets.map(petView),
        };
      },

      getShopItems() {
        const eggs = Object.values(catalog.eggs).map(egg => ({
          id: egg.key, name: egg.name, description: egg.description, cost: egg.price, category: 'pet_egg',
          image_url: `pets/eggs/${egg.key}/${egg.shop_image}`,
          owned: state.purchases.some(p => p.eggKey === egg.key && !p.petId),
        }));
        const others = otherItems.map(item => ({ ...clone(item), owned: state.items.some(o => o.itemId === item.id) }));
        return [...eggs, ...others];
      },

      // For an egg, also returns: becameActive, askToActivate (offer "make it active?") and needsSetup.
      purchaseShopItem(itemId) {
        const other = otherItems.find(i => i.id === itemId);
        if (other) {
          // Ordinary Shop items are bought once and kept, as on the site today.
          if (state.items.some(o => o.itemId === itemId)) fail(`You already own ${other.name}.`);
          if (state.gold < other.cost) fail(`Not enough gold: ${other.name} costs ${other.cost}.`);
          state.gold -= other.cost;
          const owned = { id: nextId('purchase'), itemId, boughtAt: Date.now() };
          state.items.push(owned);
          save();
          return { gold: state.gold, item: { ...clone(owned), ...clone(other) } };
        }
        const egg = catalog.eggs[itemId] || fail('That item is not in the Shop.');
        if (state.gold < egg.price) fail(`Not enough gold: ${egg.name} costs ${egg.price}.`);
        // Like the site's other items, an egg can't be bought again while one is still unhatched.
        if (state.purchases.some(p => p.eggKey === itemId && !p.petId)) fail(`You already have an unhatched ${egg.name}.`);
        state.gold -= egg.price;
        const purchase = { id: nextId('purchase'), eggKey: itemId, boughtAt: Date.now(), actionsDone: [], petId: null };
        state.purchases.push(purchase);
        // A first companion becomes active by itself; otherwise the member is asked, unless they chose "always".
        const hadActive = !!state.activeId;
        const becameActive = !hadActive || state.prefs.autoActivate;
        if (becameActive) state.activeId = purchase.id;
        save();
        return { gold: state.gold, purchase: eggView(purchase), becameActive, askToActivate: !becameActive, needsSetup: !state.prefs.setupDone };
      },

      // Ticks the action off the active egg's checklist, if it's on it. Returns that egg's progress, or null.
      recordSiteAction(actionKey) {
        if (!catalog.actions[actionKey]) fail(`Unknown action "${actionKey}".`);
        state.actions[actionKey] = state.actions[actionKey] || Date.now();
        const p = findEgg(state.activeId);
        let advanced = null;
        if (p && !p.actionsDone.includes(actionKey) && catalog.eggs[p.eggKey].hatch.actions.includes(actionKey)) {
          p.actionsDone.push(actionKey);
          advanced = { purchaseId: p.id, eggKey: p.eggKey, ...progress(p) };
        }
        save();
        return { advanced };
      },

      // Only the active egg can hatch, and the new pet takes over its active slot.
      hatchPet(purchaseId) {
        const p = state.purchases.find(x => x.id === purchaseId && x.eggKey) || fail('That egg is not yours.');
        if (p.petId) fail('That egg has already hatched.');
        if (state.activeId !== p.id) fail('Only your active companion can hatch. Make this egg active first.');
        const prog = progress(p);
        if (!prog.ready) fail(`Not ready yet: ${prog.done} / ${prog.total} done.`);
        const egg = catalog.eggs[p.eggKey];
        const seed = Math.floor(random() * 4294967296) >>> 0;
        // The server rolls with its own randomness; rollMonster gives the same odds.
        const monsterKey = Pets.rollMonster(seed, egg);
        // The skin is a second, independent roll (FLOW.md §9). The sandbox can force one for testing.
        const skin = forcedSkin !== undefined ? forcedSkin : Pets.rollSkin(catalog.monsters[monsterKey], random);
        forcedSkin = undefined;
        const pet = {
          id: nextId('pet'), purchaseId: p.id, eggKey: p.eggKey, monsterKey, skin, seed, gen_version: Pets.GEN_VERSION,
          nickname: catalog.monsters[monsterKey].name, totalXp: 0, cosmetics: {}, hatchedAt: Date.now(),
        };
        state.pets.push(pet);
        p.petId = pet.id;
        state.activeId = pet.id;
        save();
        return petView(pet);
      },

      // A finished minigame pays XP to the active companion, only if it's a pet.
      awardPetXp(won) {
        const pet = findPet(state.activeId);
        if (!pet) return { awarded: 0, pet: null, reason: findEgg(state.activeId) ? 'egg' : 'none' };
        const before = petView(pet).level;
        const amount = won ? catalog.xp.minigame_win : catalog.xp.minigame_loss;
        pet.totalXp += amount;
        state.awarded++;
        save();
        const view = petView(pet);
        return { awarded: amount, pet: view, leveledUp: view.level > before };
      },

      setActive(id) {
        if (!findPet(id) && !findEgg(id)) fail('That companion is not yours.');
        state.activeId = id;
        save();
        return { activeId: id };
      },

      renamePet(petId, nickname) {
        const pet = findPet(petId) || fail('That pet is not yours.');
        const clean = String(nickname || '').replace(/\s+/g, ' ').trim();
        if (!clean) fail('A nickname needs at least one character.');
        if (clean.length > NICKNAME_MAX) fail(`Nicknames are at most ${NICKNAME_MAX} characters.`);
        pet.nickname = clean;
        save();
        return petView(pet);
      },

      // corner: where the overlay sits; visible: false hides it (the companion stays active);
      // autoActivate: new eggs become active without asking; setupDone: the first-time setup was shown;
      // sounds: the Pet sounds setting; eggShopFound: the member has revealed the Shop's hidden Pet Eggs section.
      setPrefs(changes) {
        const next = { ...state.prefs, ...changes };
        if (!CORNERS.includes(next.corner)) fail(`Corner must be one of ${CORNERS.join(', ')}.`);
        const flags = ['visible', 'autoActivate', 'setupDone', 'sounds', 'eggShopFound'];
        for (const k of flags) if (typeof next[k] !== 'boolean') fail(`"${k}" must be true or false.`);
        state.prefs = { corner: next.corner, ...Object.fromEntries(flags.map(k => [k, next[k]])) };
        save();
        return clone(state.prefs);
      },

      // Sandbox-only helpers; the real backend has no equivalent.
      dev: {
        addGold(amount) { state.gold += amount; save(); },
        forceSkin(key) { forcedSkin = key; },   // the next hatch gets this skin (null = normal art)
        reset() { state = fresh(); save(); },
      },
    };
  }

  // Browser only: fetches every egg in pets/eggs/index.json and the monsters they hatch.
  async function loadCatalog(base = 'pets/') {
    const get = async path => {
      const res = await fetch(base + path, { cache: 'no-store' });
      if (!res.ok) throw new Error(`${base}${path}: ${res.status}`);
      return res.json();
    };
    const [keys, traits, actions, xp] = await Promise.all([get('eggs/index.json'), get('traits.json'), get('hatch-actions.json'), get('xp.json')]);
    const eggs = {}, monsters = {};
    for (const key of keys) {
      eggs[key] = await get(`eggs/${key}/egg.json`);
      for (const c of eggs[key].contents) monsters[c.monster] = monsters[c.monster] || await get(`monsters/${c.monster}/monster.json`);
    }
    return { eggs, monsters, traits, actions, xp };
  }

  const api = { createPetApi, loadCatalog, NICKNAME_MAX, START_GOLD, CORNERS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.PetApiMock = api;
})(typeof window !== 'undefined' ? window : globalThis);
