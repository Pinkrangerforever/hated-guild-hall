/* Guild War rules engine. Pure functions over a plain state object, so the same rules can run in the
   admin sandbox (browser) now and on the server later. Every action returns { ok, error?, entry } and
   appends a log entry with before/after snapshots of the zones it changed (that powers the replay).
   Time: state.clock is game hours since the start (day = floor(clock / 24)); resets happen at day starts. */
// map-data.js declares its tables as top-level consts (globals in the browser, a module in node)
const __WAR_MAP = typeof WAR_ZONES !== 'undefined' ? { WAR_ZONES, WAR_BORDERS, WAR_ROUTES, WAR_REGIONS, WAR_STRONGHOLDS } : require('./map-data.js');
(function(root){
  const M = __WAR_MAP;
  const { WAR_ZONES, WAR_BORDERS, WAR_ROUTES, WAR_REGIONS, WAR_STRONGHOLDS } = M;

  const RULES = {
    apPerDay: 5,
    baseReinforce: 3,
    startTroops: 6,           // on each starting stronghold
    garrison: [2, 4],         // neutral defenders per zone
    fortifyHours: 24,
    richPerContinent: 2,      // each game, 2 zones per resource per continent are rich deposits (16 of 43)
    richYield: 2,             // a rich zone makes 2 of its resource a day (+1 per outpost / +2 stronghold); other zones make none
    endClock: 6 * 24 + 20,    // the war ends Sunday 8pm (game clock starts Monday 00:00)
    costs: {
      outpost:    { wood: 1, food: 1, ore: 1 },
      stronghold: { ore: 2, wood: 2, crystal: 1 },
      draft:      { food: 1, ore: 1 },                // +2 reinforcements
      warcry:     { wood: 1, ore: 1 },
      shieldwall: { ore: 1, food: 1 },
      march:      { food: 1, wood: 1 },
      naval:      { wood: 2, food: 1 }
    },
    cards: {
      warcry:     'Warcry: +1 attack die for one battle',
      shieldwall: "Shield Wall: a zone ignores the attacker's best die in the first round of the next attack",
      march:      'Forced March: move from a zone that already moved today',
      naval:      'Naval Landing: attack across a boat/zeppelin route without the defender bonuses'
    }
  };

  // ---- map helpers ----
  const ADJ = {};
  Object.keys(WAR_ZONES).forEach(k => { ADJ[k] = new Set(); });
  WAR_BORDERS.forEach(([a, b]) => { ADJ[a].add(b); ADJ[b].add(a); });
  WAR_ROUTES.forEach(r => { ADJ[r.a].add(r.b); ADJ[r.b].add(r.a); });
  const SEA = new Set(WAR_ROUTES.map(r => [r.a, r.b].sort().join('|')));
  const isSeaLink = (a, b) => SEA.has([a, b].sort().join('|'));
  const PORTS = new Set(WAR_ROUTES.filter(r => r.kind === 'boat').flatMap(r => [r.a, r.b]));
  const adjacent = (a, b) => ADJ[a] && ADJ[a].has(b);
  function distances(from){
    const d = { [from]: 0 }, q = [from];
    while(q.length){ const c = q.shift(); ADJ[c].forEach(n => { if(d[n] == null){ d[n] = d[c] + 1; q.push(n); } }); }
    return d;
  }
  const enemyOf = f => f === 'horde' ? 'alliance' : 'horde';
  const day = s => Math.floor(s.clock / 24);
  const clone = o => JSON.parse(JSON.stringify(o));
  const total = z => z.ready + z.fresh;

  // ---- state ----
  function newGame(opts){
    opts = opts || {};
    return {
      v: 1, id: opts.id || ('g' + Date.now()), sandbox: !!opts.sandbox,
      phase: 'signup', clock: 0, seq: 0,
      settings: { unlimitedAP: false },
      signups: [], players: {}, zones: {}, strongholds: { horde: [], alliance: [] },
      dailyLead: { horde: 0, alliance: 0 }, log: [], result: null
    };
  }
  function log(s, entry, before){
    entry.seq = ++s.seq; entry.t = s.clock; entry.day = day(s);
    if(before){
      entry.zones = {};
      Object.keys(before).forEach(k => { entry.zones[k] = { before: before[k], after: clone(s.zones[k]) }; });
    }
    s.log.push(entry);
    return entry;
  }
  const snap = (s, ids) => { const b = {}; ids.forEach(k => { b[k] = clone(s.zones[k]); }); return b; };

  function signup(s, p){
    if(s.signups.some(x => x.id === p.id)) return { ok: false, error: 'Already signed up' };
    s.signups.push({ id: p.id, name: p.name, activity: p.activity || 0, bot: !!p.bot });
    return { ok: true, entry: log(s, { type: 'signup', pid: p.id, name: p.name }) };
  }

  // Snake draft by activity, so both factions get a mix of regulars and casuals
  function draft(list, rng){
    const sorted = list.slice().sort((a, b) => (b.activity - a.activity) || (rng() - 0.5));
    const first = rng() < 0.5 ? 'horde' : 'alliance', second = enemyOf(first);
    return sorted.map((p, i) => ({ p, faction: (Math.floor(i / 2) % 2 === 0) === (i % 2 === 0) ? first : second }));
  }

  // 2 strongholds per faction per continent, at least 2 zones from any enemy stronghold
  function pickStrongholds(rng){
    for(let tries = 0; tries < 400; tries++){
      const pick = { horde: [], alliance: [] };
      let ok = true;
      for(const cont of ['kalimdor', 'eastern']){
        const h = WAR_STRONGHOLDS.horde[cont].slice().sort(() => rng() - 0.5).slice(0, 2);
        const a = WAR_STRONGHOLDS.alliance[cont].slice().sort(() => rng() - 0.5).slice(0, 2);
        for(const x of h){ const d = distances(x); if(a.some(y => d[y] < 2)) ok = false; }
        pick.horde.push(...h); pick.alliance.push(...a);
      }
      if(ok) return pick;
    }
    return { horde: ['durotar', 'mulgore', 'tirisfal', 'badlands'], alliance: ['teldrassil', 'dustwallow', 'elwynn', 'wetlands'] };
  }

  function newPlayer(id, name, faction, bot, joinedDay){
    return { id, name, faction, bot: !!bot, ap: 0, reinforce: 0, res: { food: 0, wood: 0, ore: 0, crystal: 0 },
             cards: { warcry: 0, shieldwall: 0, march: 0, naval: 0 }, lastActiveDay: -1, joinedDay: joinedDay || 0 };
  }

  // Every zone has a resource type, but only a few randomly chosen ones are rich deposits this game,
  // so the valuable zones move around week to week and get fought over
  function pickRich(rng){
    const rich = {};
    ['food', 'wood', 'ore', 'crystal'].forEach(r => ['kalimdor', 'eastern'].forEach(c => {
      Object.keys(WAR_ZONES).filter(k => WAR_ZONES[k].resource === r && WAR_ZONES[k].continent === c)
        .sort(() => rng() - 0.5).slice(0, RULES.richPerContinent).forEach(k => { rich[k] = true; });
    }));
    return rich;
  }

  function startGame(s, rng){
    rng = rng || Math.random;
    if(s.phase !== 'signup') return { ok: false, error: 'Game already started' };
    if(s.signups.length < 2) return { ok: false, error: 'Need at least 2 players' };
    draft(s.signups, rng).forEach(({ p, faction }) => { s.players[p.id] = newPlayer(p.id, p.name, faction, p.bot, 0); });
    s.strongholds = pickStrongholds(rng);
    s.rich = pickRich(rng);
    Object.keys(WAR_ZONES).forEach(k => {
      const g = RULES.garrison[0] + Math.floor(rng() * (RULES.garrison[1] - RULES.garrison[0] + 1));
      s.zones[k] = { owner: 'neutral', ready: g, fresh: 0, fortifyUntil: 0, outpost: 0, movedDay: -1, shield: 0 };
    });
    ['horde', 'alliance'].forEach(f => s.strongholds[f].forEach(k => {
      Object.assign(s.zones[k], { owner: f, ready: RULES.startTroops, fresh: 0, outpost: 2 }); // starting strongholds are built
    }));
    s.phase = 'live'; s.clock = 0;
    log(s, { type: 'start', strongholds: clone(s.strongholds), rich: Object.keys(s.rich), teams: Object.values(s.players).map(p => ({ id: p.id, name: p.name, faction: p.faction })) },
        snap(s, Object.keys(s.zones)));
    beginDay(s, rng, true);
    return { ok: true };
  }

  // Late joiners go to the smaller faction with a catch-up pack
  function joinLate(s, p){
    if(s.phase !== 'live') return { ok: false, error: 'Game is not running' };
    if(s.players[p.id]) return { ok: false, error: 'Already in the game' };
    const count = f => Object.values(s.players).filter(x => x.faction === f).length;
    const faction = count('horde') <= count('alliance') ? 'horde' : 'alliance';
    const pl = s.players[p.id] = newPlayer(p.id, p.name, faction, p.bot, day(s));
    const d = day(s);
    pl.ap = RULES.apPerDay; pl.reinforce = reinforcementsFor(s, faction) + 2 + d * 2;
    ['food', 'wood', 'ore'].forEach(r => { pl.res[r] += d; });
    return { ok: true, entry: log(s, { type: 'join', pid: p.id, name: p.name, faction }) };
  }

  // ---- derived ----
  const zonesOf = (s, f) => Object.keys(s.zones).filter(k => s.zones[k].owner === f);
  function regionsHeld(s, f){
    return Object.keys(WAR_REGIONS).filter(r => Object.keys(WAR_ZONES).filter(k => WAR_ZONES[k].region === r).every(k => s.zones[k].owner === f));
  }
  function reinforcementsFor(s, f){
    let n = RULES.baseReinforce + Math.floor(zonesOf(s, f).length / 3);
    regionsHeld(s, f).forEach(r => { n += WAR_REGIONS[r].troops; });
    // the bigger team's players get fewer each, so both sides gain about the same per day
    const own = Object.values(s.players).filter(p => p.faction === f).length || 1;
    const opp = Object.values(s.players).filter(p => p.faction === enemyOf(f)).length || 1;
    if(own > opp) n = Math.max(2, Math.round(n * opp / own));
    return n;
  }
  // Zones linked by friendly territory (including friendly sea routes)
  function friendlyReach(s, f, from){
    const seen = new Set([from]), q = [from];
    while(q.length){ const c = q.shift(); ADJ[c].forEach(n => { if(!seen.has(n) && s.zones[n].owner === f){ seen.add(n); q.push(n); } }); }
    return seen;
  }
  function deployable(s, f){
    const bases = zonesOf(s, f).filter(k => s.zones[k].outpost >= 2);
    const set = new Set();
    bases.forEach(b => friendlyReach(s, f, b).forEach(k => set.add(k)));
    if(!set.size) zonesOf(s, f).forEach(k => set.add(k));
    return [...set];
  }
  function threat(s, k){
    const me = s.zones[k].owner; let t = 0;
    ADJ[k].forEach(n => { const z = s.zones[n]; if(z.owner !== me && z.owner !== 'neutral') t += total(z); });
    return t;
  }

  // ---- actions ----
  function actor(s, pid){
    const p = s.players[pid];
    if(s.phase !== 'live') return { error: 'The war is not running' };
    if(!p) return { error: 'Not in this game' };
    return { p };
  }
  function spendAP(s, p){
    if(s.settings.unlimitedAP) return true;
    if(p.ap < 1) return false;
    p.ap--; return true;
  }
  const active = (s, p) => { p.lastActiveDay = day(s); };
  const canPay = (p, cost) => Object.keys(cost).every(r => p.res[r] >= cost[r]);
  const pay = (p, cost) => Object.keys(cost).forEach(r => { p.res[r] -= cost[r]; });

  function deploy(s, pid, zone, n){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    n = Math.floor(n);
    if(!(n > 0) || n > p.reinforce) return { ok: false, error: 'Not enough reinforcements' };
    if(!deployable(s, p.faction).includes(zone)) return { ok: false, error: 'Deploy to a zone linked to one of your strongholds' };
    const before = snap(s, [zone]);
    s.zones[zone].fresh += n; p.reinforce -= n; active(s, p);
    return { ok: true, entry: log(s, { type: 'deploy', pid, faction: p.faction, to: zone, n }, before) };
  }

  function move(s, pid, from, to, n, opts){
    opts = opts || {};
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const a = s.zones[from], b = s.zones[to]; n = Math.floor(n);
    if(!a || !b || a.owner !== p.faction || b.owner !== p.faction || from === to) return { ok: false, error: 'Move between your own zones' };
    const d = day(s);
    if(a.movedDay === d && !opts.march) return { ok: false, error: 'Troops already marched out of here today' };
    if(opts.march && p.cards.march < 1) return { ok: false, error: 'No Forced March card' };
    if(!(n > 0) || n > a.ready || total(a) - n < 1) return { ok: false, error: 'Only ready troops can move, and one must stay' };
    if(!friendlyReach(s, p.faction, from).has(to)) return { ok: false, error: 'No friendly path to that zone' };
    if(!spendAP(s, p)) return { ok: false, error: 'No action points left' };
    const before = snap(s, [from, to]);
    if(opts.march) p.cards.march--;
    a.ready -= n; b.fresh += n; a.movedDay = d; active(s, p);
    return { ok: true, entry: log(s, { type: 'move', pid, faction: p.faction, from, to, n, march: !!opts.march }, before) };
  }

  function rollDice(k, rng){ return Array.from({ length: k }, () => 1 + Math.floor(rng() * 6)).sort((x, y) => y - x); }

  function attack(s, pid, from, to, n, opts, rng){
    opts = opts || {}; rng = rng || Math.random;
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const a = s.zones[from], b = s.zones[to]; n = Math.floor(n);
    if(!a || !b || a.owner !== p.faction) return { ok: false, error: 'Attack from one of your zones' };
    if(b.owner === p.faction) return { ok: false, error: "That zone is already yours" };
    if(!adjacent(from, to)) return { ok: false, error: 'You can only attack a bordering zone' };
    if(!(n > 0) || n > a.ready || total(a) - n < 1) return { ok: false, error: 'Only ready troops can attack, and one must stay' };
    const naval = !!opts.naval;
    if(naval && !isSeaLink(from, to)) return { ok: false, error: 'Naval Landing needs a boat or zeppelin route' };
    if(naval && p.cards.naval < 1) return { ok: false, error: 'No Naval Landing card' };
    if(opts.warcry && p.cards.warcry < 1) return { ok: false, error: 'No Warcry card' };
    if(!spendAP(s, p)) return { ok: false, error: 'No action points left' };
    if(naval) p.cards.naval--;
    if(opts.warcry) p.cards.warcry--;
    const before = snap(s, [from, to]);
    const defender = b.owner;
    const info = WAR_ZONES[to];
    const fortified = !naval && b.fortifyUntil > s.clock;
    const defBonus = naval ? 0 : (fortified ? 1 : 0) + (info.capital ? 1 : 0) + (b.outpost >= 2 ? 1 : 0);
    const defExtraDie = !naval && b.outpost >= 1 ? 1 : 0;
    let att = n, def = total(b);
    const rounds = [];
    let shield = b.shield > 0;
    while(att > 0 && def > 0 && rounds.length < 200){
      let ad = rollDice(Math.min(3 + (opts.warcry ? 1 : 0), att + (opts.warcry ? 1 : 0)), rng);
      let dd = rollDice(Math.min(2 + defExtraDie, def), rng);
      if(opts.forceDice === 'att'){ ad = ad.map(() => 6); dd = dd.map(() => 1); }      // admin sandbox only
      if(opts.forceDice === 'def'){ ad = ad.map(() => 1); dd = dd.map(() => 6); }
      const ddAdj = dd.map((v, i) => i === 0 ? v + defBonus : v);
      let adUse = ad.slice();
      if(shield){ adUse = adUse.slice(1); shield = false; b.shield = 0; }
      let al = 0, dl = 0;
      for(let i = 0; i < Math.min(adUse.length, ddAdj.length); i++){ if(adUse[i] > ddAdj[i]) dl++; else al++; }
      al = Math.min(al, att); dl = Math.min(dl, def);
      att -= al; def -= dl;
      rounds.push({ ad, dd, bonus: defBonus, al, dl });
    }
    const losses = n - att;
    a.ready -= n;                               // the attacking force left the zone
    let captured = false;
    if(def === 0){
      captured = true;
      Object.assign(b, { owner: p.faction, ready: 0, fresh: att, fortifyUntil: 0, outpost: 0, movedDay: day(s), shield: 0 });
    } else {
      a.ready += att;                           // survivors fall back
      // defenders lose fresh troops first, then ready
      let dlost = total(b) - def; const takeFresh = Math.min(b.fresh, dlost); b.fresh -= takeFresh; b.ready -= (dlost - takeFresh);
    }
    active(s, p);
    return { ok: true, entry: log(s, { type: 'attack', pid, faction: p.faction, defender, from, to, n, rounds, attLost: losses,
      defLost: before[to].ready + before[to].fresh - (captured ? 0 : def), captured, survivors: att, fortified, naval, warcry: !!opts.warcry }, before) };
  }

  function fortify(s, pid, zone){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const z = s.zones[zone];
    if(!z || z.owner !== p.faction) return { ok: false, error: 'Fortify one of your zones' };
    if(!spendAP(s, p)) return { ok: false, error: 'No action points left' };
    const before = snap(s, [zone]);
    z.fortifyUntil = s.clock + RULES.fortifyHours; active(s, p);
    return { ok: true, entry: log(s, { type: 'fortify', pid, faction: p.faction, to: zone, until: z.fortifyUntil }, before) };
  }

  function build(s, pid, zone, kind){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const z = s.zones[zone];
    if(!z || z.owner !== p.faction) return { ok: false, error: 'Build in one of your zones' };
    if(kind === 'outpost' && z.outpost >= 1) return { ok: false, error: 'Already has an outpost' };
    if(kind === 'stronghold' && z.outpost !== 1) return { ok: false, error: 'Upgrade an outpost into a stronghold' };
    const cost = RULES.costs[kind];
    if(!canPay(p, cost)) return { ok: false, error: 'Not enough resources' };
    if(!spendAP(s, p)) return { ok: false, error: 'No action points left' };
    const before = snap(s, [zone]);
    pay(p, cost); z.outpost = kind === 'outpost' ? 1 : 2; active(s, p);
    return { ok: true, entry: log(s, { type: 'build', pid, faction: p.faction, to: zone, kind }, before) };
  }

  function craft(s, pid, kind){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const cost = RULES.costs[kind];
    if(!cost || kind === 'outpost' || kind === 'stronghold') return { ok: false, error: 'Unknown card' };
    if(!canPay(p, cost)) return { ok: false, error: 'Not enough resources' };
    pay(p, cost);
    if(kind === 'draft') p.reinforce += 2; else p.cards[kind]++;
    active(s, p);
    return { ok: true, entry: log(s, { type: 'craft', pid, faction: p.faction, kind }) };
  }

  function useShieldWall(s, pid, zone){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const z = s.zones[zone];
    if(!z || z.owner !== p.faction) return { ok: false, error: 'Use it on one of your zones' };
    if(p.cards.shieldwall < 1) return { ok: false, error: 'No Shield Wall card' };
    const before = snap(s, [zone]);
    p.cards.shieldwall--; z.shield = 1; active(s, p);
    return { ok: true, entry: log(s, { type: 'shieldwall', pid, faction: p.faction, to: zone }, before) };
  }

  function tradeRate(s, f){ return zonesOf(s, f).some(k => PORTS.has(k)) ? 3 : 4; }
  function trade(s, pid, give, get){
    const { p, error } = actor(s, pid); if(error) return { ok: false, error };
    const rate = tradeRate(s, p.faction);
    if(give === get || !(give in p.res) || !(get in p.res)) return { ok: false, error: 'Pick two different resources' };
    if(p.res[give] < rate) return { ok: false, error: `Need ${rate} ${give}` };
    p.res[give] -= rate; p.res[get] += 1; active(s, p);
    return { ok: true, entry: log(s, { type: 'trade', pid, faction: p.faction, give, get, rate }) };
  }

  // ---- daily reset ----
  function autopilot(s){
    // players who never played today: their unused reinforcements go to the most threatened zones
    const d = day(s);
    Object.values(s.players).forEach(p => {
      if(p.lastActiveDay === d || p.reinforce <= 0) return;
      const spots = deployable(s, p.faction).sort((a, b) => threat(s, b) - threat(s, a));
      if(!spots.length) return;
      const before = snap(s, spots.slice(0, 3));
      let left = p.reinforce, i = 0; const placed = {};
      while(left > 0){ const k = spots[i % Math.min(3, spots.length)]; s.zones[k].fresh++; placed[k] = (placed[k] || 0) + 1; left--; i++; }
      p.reinforce = 0;
      log(s, { type: 'autopilot', pid: p.id, faction: p.faction, placed }, before);
    });
  }
  function beginDay(s, rng, first){
    rng = rng || Math.random;
    if(!first){
      autopilot(s);
      s.clock = (day(s) + 1) * 24;
    }
    const d = day(s);
    const allIds = Object.keys(s.zones);
    const before = snap(s, allIds);
    allIds.forEach(k => { const z = s.zones[k]; z.ready += z.fresh; z.fresh = 0; });   // fresh troops are ready now
    // daily lead point
    const hz = zonesOf(s, 'horde').length, az = zonesOf(s, 'alliance').length;
    if(!first && hz !== az) s.dailyLead[hz > az ? 'horde' : 'alliance']++;
    // production (only rich deposits; games saved before rich deposits existed: every zone makes 1) -> players who played yesterday (others get every other unit)
    const produced = { horde: {}, alliance: {} };
    ['horde', 'alliance'].forEach(f => {
      const team = Object.values(s.players).filter(p => p.faction === f);
      if(!team.length) return;
      const recent = team.filter(p => p.lastActiveDay >= d - 1);
      const pool = [];
      zonesOf(s, f).forEach(k => { const z = s.zones[k], r = WAR_ZONES[k].resource; if(s.rich && !s.rich[k]) return; const amt = (s.rich ? RULES.richYield : 1) + (z.outpost || 0); for(let i = 0; i < amt; i++) pool.push(r); produced[f][r] = (produced[f][r] || 0) + amt; });
      const takers = recent.length ? recent : team;
      pool.forEach((r, i) => { takers[i % takers.length].res[r]++; });
      team.forEach(p => {
        p.ap = RULES.apPerDay;
        p.reinforce += reinforcementsFor(s, f);
      });
    });
    log(s, { type: 'dawn', produced, lead: clone(s.dailyLead), reinforce: { horde: reinforcementsFor(s, 'horde'), alliance: reinforcementsFor(s, 'alliance') } }, before);
  }

  function score(s){
    const out = {};
    ['horde', 'alliance'].forEach(f => {
      const zs = zonesOf(s, f);
      const outposts = zs.filter(k => s.zones[k].outpost === 1).length;
      const holds = zs.filter(k => s.zones[k].outpost === 2).length;
      const regions = regionsHeld(s, f);
      const enemyHolds = s.strongholds[enemyOf(f)].filter(k => s.zones[k].owner === f).length;
      const parts = { zones: zs.length, outposts, strongholds: holds * 2, regions: regions.reduce((a, r) => a + WAR_REGIONS[r].points, 0),
                      enemyStrongholds: enemyHolds * 3, dailyLead: s.dailyLead[f] };
      out[f] = { parts, total: Object.values(parts).reduce((a, b) => a + b, 0), regions };
    });
    return out;
  }
  function endGame(s){
    if(s.phase !== 'live') return { ok: false, error: 'Game is not running' };
    const sc = score(s);
    s.phase = 'ended';
    s.result = { score: sc, winner: sc.horde.total === sc.alliance.total ? 'draw' : (sc.horde.total > sc.alliance.total ? 'horde' : 'alliance') };
    return { ok: true, entry: log(s, { type: 'end', result: s.result }) };
  }

  const warOver = s => s.clock >= RULES.endClock;
  const isRich = (s, k) => !!(s.rich && s.rich[k]);
  const api = { RULES, isRich, pickRich, warOver, ADJ, PORTS, isSeaLink, adjacent, distances, newGame, signup, startGame, joinLate, beginDay, deploy, move, attack, fortify,
                build, craft, useShieldWall, trade, tradeRate, endGame, score, reinforcementsFor, deployable, friendlyReach, regionsHeld, zonesOf, day, enemyOf, threat };
  if(typeof module !== 'undefined') module.exports = api; else root.WarEngine = api;
})(typeof window !== 'undefined' ? window : globalThis);
