// Guild War server: every war action goes through here.
//
// The browser never writes the war. It calls this function with { action, ...args }; we check who is signed in,
// load the war, run the shared engine (game.js, bundled from guild-war/*.js by tools/build_war_server.py), and
// save the result with the service role. New log entries go into guild_war_log, which streams live to every
// board. Saves use the row's `version` so two actions at once can't overwrite each other: on a clash we reload
// and try again.
//
// The war clock runs on Pacific time: the game clock is hours since the war's Monday 00:00 PT (weekStart). Before
// any action we "catch up": run every dawn (with the 11:59pm autopilot) that has passed and end the war at Sunday
// 8pm. A pg_cron job also calls { action: 'tick' } every 10 minutes, so days turn even when nobody plays.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { E, AI } from './game.js';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const db = createClient(URL_, SERVICE, { auth: { persistSession: false } });

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
const HOUR = 3600 * 1000;
const isUuid = (x: string) => /^[0-9a-f-]{36}$/.test(x);

// ---------- Pacific time ----------
// offset (ms) of America/Los_Angeles from UTC at a moment, e.g. -7h in summer
function laOffset(at: number): number {
  const p: any = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/Los_Angeles', hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
    .formatToParts(new Date(at)).filter(x => x.type !== 'literal').map(x => [x.type, +x.value]));
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - Math.floor(at / 1000) * 1000;
}
// PT midnight starting the PT day that contains `at`, moved by `addDays`
function laMidnight(at: number, addDays = 0): number {
  const local = new Date(at + laOffset(at));
  const guess = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + addDays);
  return guess - laOffset(guess);
}
// the next Monday 00:00 PT after `at`
function nextMondayLA(at: number): number {
  const dow = new Date(at + laOffset(at)).getUTCDay();   // 0 Sunday .. 6 Saturday
  return laMidnight(at, ((8 - dow) % 7) || 7);
}
// game hours since the war's first midnight, counting real PT days so DST doesn't move the day boundaries
function gameHours(weekStart: number, now: number): number {
  let days = 0; while(days < 8 && laMidnight(weekStart, days + 1) <= now) days++;
  return days * 24 + (now - laMidnight(weekStart, days)) / HOUR;
}

// ---------- the war rows ----------
type Game = { id: string; state: any; version: number; active: boolean };
async function activeGame(): Promise<Game | null> {
  const { data, error } = await db.from('guild_war_games').select('*').eq('active', true).maybeSingle();
  if(error) throw error;
  return data as Game | null;
}
async function gameById(id: string): Promise<Game | null> {
  const { data } = await db.from('guild_war_games').select('*').eq('id', id).maybeSingle();
  return data as Game | null;
}

// a signed-in player's site pet, if it has hatched (pets cap at level 10): the one they picked for the war (the
// War Room's pet picker), or else their highest level one
async function petOf(uid: string, pick?: string) {
  let q = db.from('pets').select('id,pet_type,name,level,status').eq('user_id', uid).neq('status', 'egg');
  if(pick) q = q.eq('id', pick);
  const { data, error } = await q.order('level', { ascending: false }).limit(1);
  if(error){ console.error('pet lookup failed', error); return undefined; }   // undefined = try again later
  const p = data && data[0];
  if(!p && pick) return petOf(uid);   // the picked pet is gone (released): back to the best one
  return p ? { id: p.id, type: p.pet_type, status: p.status, level: Math.min(10, p.level || 1), name: p.name || 'Pet' } : null;
}
// test bots: same names and pets as the sandbox
const BOT_NAMES = ['Thrall', 'Jaina', 'Sylvanas', 'Varian', 'Grommash', 'Tyrande', 'Garrosh', 'Muradin', 'Voljin', 'Genn', 'Baine', 'Velen'];
function botPet() {
  if(Math.random() >= 0.7) return null; const lv = 1 + Math.floor(Math.random() * 10);
  return { type: ['gryphon', 'dragon', 'cat', 'phoenix'][Math.floor(Math.random() * 4)], status: lv >= 10 ? 'boss' : lv >= 5 ? 'adult' : 'juvenile', level: lv, name: ['Fluffy', 'Snaps', 'Ember', 'Biscuit', 'Talon', 'Mr. Whiskers'][Math.floor(Math.random() * 6)] };
}
// bots put their pet on their most threatened zone whenever it's free to go
function stationBotPets(s: any) {
  if(s.phase !== 'live') return;
  Object.values(s.players).forEach((p: any) => {
    if(!p.bot || !p.pet || !E.petUp(s, p) || E.petOnBoard(s, p)) return;
    const k = E.deployable(s, p.faction).filter((k: string) => !E.petIn(s, k)).sort((a: string, b: string) => E.threat(s, b) - E.threat(s, a))[0];
    if(k) E.placePet(s, p.id, k);
  });
}

// Run `fn` on a war's state and save it; retries if someone else saved in between.
// Without opts.gameId it works on the active war (creating one with opts.create if there is none).
async function mutate(fn: (s: any, g: Game) => any, opts: { create?: () => any, gameId?: string } = {}) {
  for(let attempt = 0; attempt < 6; attempt++){
    let g = opts.gameId ? await gameById(opts.gameId) : await activeGame();
    if(!g && opts.create){
      const s0 = opts.create();
      const { data, error } = await db.from('guild_war_games').insert({ id: s0.id, state: s0, version: 0, active: true, week_start: s0.weekStart ? new Date(s0.weekStart).toISOString() : null }).select().single();
      if(error){ if(error.code === '23505') continue; throw error; }   // someone else made one first
      g = data as Game;
    }
    if(!g) return { ok: false, error: 'No war is running' };
    const s = g.state; s.log = [];
    const r = (await fn(s, g)) || { ok: true };
    if(r.ok === false && !s.log.length) return r;
    // everyone who has appeared in the war gets their pet (real players: their site pet; bots: their test pet);
    // bots then station theirs (which logs a move, so this happens before the new entries are collected)
    for(const p of Object.values(s.players) as any[]){
      // real players' pets are looked up again every 10 minutes: a new pet joins, a levelled-up one gets stronger
      const stale = !p.bot && isUuid(p.id) && !(p.petCheckedAt > Date.now() - 10 * 60 * 1000);
      if(p.pet !== undefined && !stale) continue;
      if(p.bot){ p.pet = (s.botPets || {})[p.id] || null; continue; }
      const pet = isUuid(p.id) ? await petOf(p.id, p.petPick) : null;
      if(pet !== undefined){ p.pet = pet ? Object.assign(p.pet || {}, pet) : null; p.petCheckedAt = Date.now(); }
    }
    stationBotPets(s);
    const entries = s.log; delete s.log;
    // the war just ended: keep each player's final stats with it (the end screen and the champion use them)
    if(s.phase === 'ended' && !s.stats){
      const { data: rows } = await db.from('guild_war_log').select('entry').eq('game_id', g.id).order('seq');
      const st = AI.playerStats(s, (rows || []).map((x: any) => x.entry).concat(entries));
      s.stats = {}; Object.values(st).forEach((x: any) => { s.stats[x.p.id] = { caps: x.caps, kills: x.kills, builds: x.builds, forts: x.forts, score: x.score }; });
    }
    // each entry carries the acting player's public bits so other boards can keep their ledger current
    entries.forEach((e: any) => { const p = e.pid && s.players[e.pid]; if(p) e.pl = { id: p.id, name: p.name, bot: !!p.bot, faction: p.faction, lastActiveDay: p.lastActiveDay, petZone: p.petZone ?? null, petDown: p.petDown ?? 0, pet: p.pet ?? null }; });
    const { data: upd, error } = await db.from('guild_war_games').update({ state: s, version: g.version + 1, updated_at: new Date().toISOString() })
      .eq('id', g.id).eq('version', g.version).select('id');
    if(error) throw error;
    if(!upd || !upd.length) continue;   // version clash: reload and redo
    if(entries.length){
      const { error: le } = await db.from('guild_war_log').insert(entries.map((e: any) => ({ game_id: g!.id, seq: e.seq, entry: e })));
      if(le) console.error('log insert failed', le);
    }
    await afterSave(s, g, entries);
    return { ...r, entry: undefined, ok: r.ok !== false, seq: s.seq, entries };   // the new moves, so the caller can play them at once
  }
  return { ok: false, error: 'The war is busy, try again' };
}

// bring the war up to the present: the scheduled start, every dawn that has passed, and the end at Sunday 8pm
function catchUp(s: any, now: number) {
  if(s.phase === 'signup' && s.weekStart && now >= s.weekStart){
    if(s.signups.length >= 2){ E.startGame(s); s.startedAt = now; }
    else s.weekStart = nextMondayLA(now);   // not enough people: sign-ups stay open for next Monday
  }
  if(s.phase !== 'live' || !s.weekStart) return;
  const target = gameHours(s.weekStart, now);
  while(E.day(s) < Math.min(6, Math.floor(target / 24))) E.beginDay(s);
  if(target >= E.RULES.endClock){ s.clock = E.RULES.endClock; E.endGame(s); s.endedAt = now; }
  else s.clock = Math.max(s.clock, target);
}
// side effects after a save: faction chat membership and medals for the winners
async function afterSave(s: any, g: Game, entries: any[]) {
  const types = new Set(entries.map((e: any) => e.type));
  if(types.has('start') || types.has('join')){
    const rows = Object.values(s.players).filter((p: any) => !p.bot && isUuid(p.id)).map((p: any) => ({ user_id: p.id, faction: p.faction, updated_at: new Date().toISOString() }));
    if(rows.length) await db.from('guild_war_members').upsert(rows);
  }
  if(types.has('end') && s.result){
    const win = s.result.winner;   // a draw gives no medals
    if(win === 'horde' || win === 'alliance'){
      const rows = Object.values(s.players).filter((p: any) => !p.bot && isUuid(p.id) && p.faction === win).map((p: any) => ({ user_id: p.id, game_id: g.id, faction: win, kind: 'victory' }));
      if(rows.length) await db.from('guild_war_medals').upsert(rows, { onConflict: 'user_id,game_id,kind', ignoreDuplicates: true });
    }
  }
}
// the winning side's top scorer (top overall in a draw) may smash the board until the next war starts
function champion(s: any) {
  if(s.phase !== 'ended' || !s.result || !s.stats) return null;
  const win = s.result.winner, pool = Object.keys(s.stats).filter(id => s.players[id] && (win === 'draw' || s.players[id].faction === win));
  const best = pool.sort((a, b) => s.stats[b].score - s.stats[a].score)[0];
  return best && s.stats[best].score > 0 ? best : null;
}
const newWar = (now: number, auto: boolean) => { const s = E.newGame({ id: 'g' + now }); if(auto){ s.auto = true; s.weekStart = nextMondayLA(now); } return s; };

Deno.serve(async req => {
  if(req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try{
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || '');
    const now = Date.now();

    // ----- the clock: anyone (and the cron job) may bring the war up to the present; it only does what time says -----
    if(action === 'tick'){
      const g = await activeGame(); if(!g) return reply({ ok: true, idle: true });
      // a weekly war that has ended: when its smash window closes (the next sign-ups open at Sunday 8pm), roll over
      if(g.state.phase === 'ended' && g.state.auto){
        await db.from('guild_war_games').update({ active: false }).eq('id', g.id).eq('version', g.version);
        return reply(await mutate(() => ({ ok: true }), { create: () => newWar(now, true) }));
      }
      return reply(await mutate(s => { catchUp(s, now); return { ok: true }; }));
    }

    // ----- everything else needs a signed-in member -----
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    // check the sign-in and load the profile at the same time: the token says who it claims to be, and the
    // profile is only used once Supabase Auth has confirmed it
    let claimed = '';
    try{ claimed = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub || ''; }catch(_){ /* not a token */ }
    const [{ data: au }, { data: prof0 }] = await Promise.all([
      createClient(URL_, ANON).auth.getUser(token),
      isUuid(claimed) ? db.from('profiles').select('id, character_name, protected, gold_earned_total').eq('id', claimed).maybeSingle() : Promise.resolve({ data: null })
    ]);
    const uid = au?.user?.id; if(!uid) return reply({ ok: false, error: 'Sign in first' }, 401);
    const prof = prof0 && prof0.id === uid ? prof0 : null;
    if(!prof) return reply({ ok: false, error: 'No profile' }, 403);
    const name = prof.character_name || 'Unknown', admin = !!prof.protected;

    // ----- admin controls (the protected Raid Leader account) -----
    if(action.startsWith('admin_')){
      if(!admin) return reply({ ok: false, error: 'Raid Leader only' }, 403);
      // tell the clock job where we live (staging and prod have different addresses)
      await db.from('guild_war_config').upsert({ key: 'tick_url', value: URL_ + '/functions/v1/war', updated_at: new Date().toISOString() });
      if(action === 'admin_new'){
        // body.auto: a weekly war (sign-ups now, starts next Monday 00:00 PT); otherwise a test war you start by hand
        const g = await activeGame(); if(g) await db.from('guild_war_games').update({ active: false }).eq('id', g.id);
        return reply(await mutate(() => ({ ok: true }), { create: () => newWar(now, !!body.auto) }));
      }
      if(action === 'admin_close'){ const g = await activeGame(); if(g) await db.from('guild_war_games').update({ active: false }).eq('id', g.id); return reply({ ok: true }); }
      return reply(await mutate(s => {
        catchUp(s, now);
        switch(action){
          case 'admin_start': {
            if(s.phase !== 'signup') return { ok: false, error: 'Sign-ups are not open' };
            s.weekStart = laMidnight(now); s.startedAt = now;   // a test war runs on real days from today's midnight
            const r = E.startGame(s); if(!r.ok) return r;
            s.clock = gameHours(s.weekStart, now); return { ok: true };
          }
          case 'admin_next_day': {
            // time travel for testing: the war's week starts a day earlier, then catching up runs the dawn
            if(s.phase !== 'live') return { ok: false, error: 'The war is not running' };
            s.weekStart = laMidnight(s.weekStart, -1); catchUp(s, now); return { ok: true };
          }
          case 'admin_end': if(s.phase !== 'live') return { ok: false, error: 'The war is not running' }; E.endGame(s); s.endedAt = now; return { ok: true };
          case 'admin_bots': {
            const n = Math.max(1, Math.min(10, +body.n || 1)), used = new Set([...s.signups.map((x: any) => x.name), ...Object.values(s.players).map((p: any) => p.name)]);
            s.botPets = s.botPets || {};
            for(let i = 0; i < n; i++){
              const nm = BOT_NAMES.find(x => !used.has(x)) || ('Bot ' + (used.size + 1)); used.add(nm);
              const id = 'bot-' + Math.random().toString(36).slice(2, 8);
              s.botPets[id] = botPet();
              if(s.phase === 'signup') E.signup(s, { id, name: nm, activity: Math.floor(Math.random() * 100), bot: true });
              else if(s.phase === 'live') E.joinLate(s, { id, name: nm, bot: true });
            }
            return { ok: true };
          }
          case 'admin_run_bots': {
            if(s.phase !== 'live') return { ok: false, error: 'The war is not running' };
            Object.keys(s.players).filter(id => s.players[id].bot).sort(() => Math.random() - 0.5).forEach(id => { E.scout(s, id); AI.botTurn(E, s, id); });
            return { ok: true };
          }
          case 'admin_unlimited_ap': s.settings.unlimitedAP = !!body.on; return { ok: true };
        }
        return { ok: false, error: 'Unknown admin action' };
      }));
    }

    // ----- the champion's smash: on the war that just ended (sign-ups for the next one may already be open) -----
    if(action === 'smash'){
      const { data: last } = await db.from('guild_war_games').select('id, state').order('created_at', { ascending: false }).limit(2);
      const ended = (last || []).find((x: any) => x.state && x.state.phase === 'ended');
      if(!ended || (last || []).some((x: any) => x.state && x.state.phase === 'live')) return reply({ ok: false, error: 'There is no finished war to smash' });
      return reply(await mutate(s => {
        if(champion(s) !== uid) return { ok: false, error: 'Only the champion can smash the board' };
        s.smash = s.smash || []; s.smashStart = s.smashStart || now;
        if(s.smash.length >= 300) return { ok: false, error: 'The board is already in pieces' };
        const hit = { x: +(+body.x).toFixed(3), z: +(+body.z).toFixed(3), power: +(0.8 + Math.random() * 0.5).toFixed(2), seed: Math.floor(Math.random() * 1e9), t: +((now - s.smashStart) / 1000).toFixed(2) };
        if(!isFinite(hit.x) || !isFinite(hit.z)) return { ok: false, error: 'Bad spot' };
        s.smash.push(hit); return { ok: true, hit, gameId: ended.id };
      }, { gameId: ended.id }));
    }

    // ----- player actions on the active war -----
    // (the reply carries the player's own record - AP, troops to deploy, resources, cards - which only they see change)
    let mine: any = null;
    // choosing which pet fights: look the pet up first (it must be theirs and hatched)
    let picked: any = null;
    if(action === 'pickpet'){
      if(!isUuid(String(body.petId || ''))) return reply({ ok: false, error: 'Pick one of your pets' });
      picked = await petOf(uid, body.petId);
      if(!picked || picked.id !== body.petId) return reply({ ok: false, error: 'That pet cannot fight (eggs stay home)' });
    }
    const res = await mutate(s => {
      const out = playerAction(s);
      mine = s.players[uid] || null;
      return out;
    });
    return reply({ ...res, me: res.ok ? mine : undefined });
    function playerAction(s: any): any {
      catchUp(s, now);
      const me = s.players[uid];
      if(action === 'tickme') return { ok: true };
      if(action === 'signup'){
        if(s.phase !== 'signup') return { ok: false, error: 'Sign-ups are closed' };
        return E.signup(s, { id: uid, name, activity: Math.min(100, Math.round((prof.gold_earned_total || 0) / 50)) });
      }
      if(action === 'join'){
        if(s.phase !== 'live') return { ok: false, error: 'The war is not running' };
        if(me) return { ok: false, error: 'You are already in this war' };
        return E.joinLate(s, { id: uid, name });
      }
      if(!me) return { ok: false, error: 'You are not in this war' };
      switch(action){
        case 'scout': return E.scout(s, uid);
        case 'deploy': return E.deploy(s, uid, body.zone, body.n);
        case 'move': return E.move(s, uid, body.from, body.to, body.n, { march: !!body.march, pet: !!body.pet });
        case 'attack': return E.attack(s, uid, body.from, body.to, body.n, { warcry: !!body.warcry, naval: !!body.naval, pet: !!body.pet });
        case 'fortify': return E.fortify(s, uid, body.zone);
        case 'build': return E.build(s, uid, body.zone, body.kind);
        case 'craft': return E.craft(s, uid, body.kind);
        case 'shieldwall': return E.useShieldWall(s, uid, body.zone);
        case 'trade': return E.trade(s, uid, body.give, body.get);
        case 'pet': return E.placePet(s, uid, body.zone);
        case 'petmove': return E.movePet(s, uid, body.to);
        case 'rat': {   // caught one of the War Room's rats: a tally for the end screen (at most one every 20 s)
          if(me.ratAt && Date.now() - me.ratAt < 20000) return { ok: false, error: 'That rat got away' };
          me.rats = (me.rats || 0) + 1; me.ratAt = Date.now(); return { ok: true };
        }
        case 'pickpet':   // switch only while your pet is off the board (not guarding a zone); its recovery time stays
          if(E.petOnBoard(s, me)) return { ok: false, error: 'Your pet is on the board: you can switch while it is off the board' };
          me.petPick = picked.id; me.pet = picked; me.petCheckedAt = Date.now(); return { ok: true };
      }
      return { ok: false, error: 'Unknown action' };
    }
  }catch(err){
    console.error(err);
    return reply({ ok: false, error: 'Server error: ' + ((err as any)?.message || err) }, 500);
  }
});
