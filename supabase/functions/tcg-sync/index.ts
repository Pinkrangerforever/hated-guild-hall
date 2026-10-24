// tcg-sync: credits Hated TCG points from the Hated Companion addon's kill log, and lets the Raid Leader review held
// syncs. The addon only logs kills; this decides what they're worth and whether they look real. Points are
// account-wide (every character adds to one pool).
//
// POST { action: 'sync', entries: string[], tampered?: boolean }
//   -> { ok, points, counted, skipped, held, balance, summary, flags, code }
// POST { action: 'review', id: number, decision: 'approve' | 'reject' }   (Raid Leader)
//
// Log lines (from addons/HatedCompanion/HatedTCG.lua):
//   m,<time>,<char>,<char level>,<npc id>,<spawn guid>,<instance id>,<map id>,<mob level>,<classification>,<addon estimate>
//   b,<time>,<char>,<char level>,<encounter id>,<r|d>,<instance id>,<difficulty>,<group size>,<group members>,<addon estimate>
// addon 3.7+ (HTCG6) adds, after the name field (11): m lines ,<creature type letter>,<faction H|A>; b lines ,<dungeon key>,<faction>
//   (they feed the daily challenges: daily.ts)
// addon 3.8+ (HTCG7) adds to both: ,<drop group>,<class> (fields 14, 15): card drops, drops.ts
//
// Counting each kill once: the account remembers the newest kill time it has counted (last_t). A sync only counts
// lines newer than that, so syncing the same file again adds nothing. Raid / dungeon boss lockouts are kept as keys.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { DAILY, board, dungeonDone, pacificDay, taskCount, type Prog } from './daily.ts';
import { expectedDrops, killKind, luckChance, rarityOf, roll, validClass, validGroup } from './drops.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// the rules
const FIRST = 10, REPEAT = 1, REPEAT_ELITE = 3;
const DUNGEON_BOSS = 10, DUNGEON_LAST = 20, RAID_FIRST = 100, RAID_REPEAT = 20;
const MAX_AGE = 31 * 86400;              // the addon keeps 30 days
// Kills before this moment never count (the clean start at launch: addons still hold older kill logs). Set the
// TCG_START secret to a unix time in seconds (e.g. the launch moment); unset = no cutoff.
const TCG_START = Number(Deno.env.get('TCG_START') || 0) || 0;
const MAX_ENTRIES = 100000;
const DAILY_CLAIM_DAYS = 7;              // a daily board can be paid up to this many days later
const LUCK_LIMIT = 1e-4;                 // drops this unlikely (1 in 10,000) are held for the Raid Leader
// suspicion: held for the Raid Leader instead of credited
const MAX_KILLS_PER_MINUTE = 40, MAX_KILLS_PER_DAY = 6000, MAX_LEVELS_ABOVE = 15;

const greyLevel = (p: number) => p <= 5 ? 0 : p <= 39 ? p - 5 - Math.floor(p / 10) : p <= 59 ? p - 1 - Math.floor(p / 5) : p - 9;
const ELITE = new Set(['elite', 'rareelite', 'worldboss']);
const dayOf = (t: number) => new Date(t * 1000).toISOString().slice(0, 10);
// the code a player pastes into the addon to show their balance in game (a checksum catches typos)
const balanceCode = (points: number, lifetime: number, lastT: number) => {
  const body = `${points}:${lifetime}:${lastT}`;
  let h = 7; for (const c of body) h = (h * 31 + c.charCodeAt(0)) % 1000003;
  return `HTCG:${body}:${h}`;
};

const collectionCode = (points: number, lifetime: number, lastT: number, cards: string, decks: string) => {
  const body = `${points}:${lifetime}:${lastT}:${cards}:${decks}`;
  let h = 7; for (const c of body) h = (h * 31 + c.charCodeAt(0)) % 1000003;
  return `HTCG3:${body}:${h}`;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const { data: u, error: ue } = await createClient(URL_, ANON).auth.getUser(token);
  if (ue || !u?.user) return json({ error: 'Sign in first' }, 401);
  const uid = u.user.id;
  const db = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  let body: any; try { body = await req.json(); } catch (_) { return json({ error: 'Bad request' }, 400); }

  // ---------- the Raid Leader reviews a held sync ----------
  if (body.action === 'review') {
    const { data: me } = await db.from('profiles').select('protected').eq('id', uid).maybeSingle();
    if (!me?.protected) return json({ error: 'Only the Raid Leader can review TCG syncs' }, 403);
    const { data: s } = await db.from('tcg_syncs').select('*').eq('id', body.id).maybeSingle();
    if (!s || s.status !== 'held') return json({ error: 'That sync is not waiting for review' }, 400);
    const approve = body.decision === 'approve';
    const { data: acct } = await db.from('tcg_accounts').select('*').eq('user_id', s.user_id).maybeSingle();
    if (acct) {
      await db.from('tcg_accounts').update({
        held: Math.max(0, acct.held - s.points),
        points: acct.points + (approve ? s.points : 0), lifetime: acct.lifetime + (approve ? s.points : 0), updated_at: new Date().toISOString(),
      }).eq('user_id', s.user_id);
    }
    await db.from('tcg_syncs').update({ status: approve ? 'approved' : 'rejected', reviewed_by: uid, reviewed_at: new Date().toISOString() }).eq('id', s.id);
    return json({ ok: true });
  }

  // ---------- the Raid Leader reviews card drops held by the luck check ----------
  if (body.action === 'review_drops') {
    const { data: me } = await db.from('profiles').select('protected').eq('id', uid).maybeSingle();
    if (!me?.protected) return json({ error: 'Only the Raid Leader can review card drops' }, 403);
    const { data: h } = await db.from('tcg_held_drops').select('*').eq('id', body.id).maybeSingle();
    if (!h || h.status !== 'held') return json({ error: 'Those drops are not waiting for review' }, 400);
    const approve = body.decision === 'approve';
    if (approve) {
      const { error: ae } = await db.rpc('tcg_add_drops', { p_user: h.user_id, p_drops: h.drops });
      if (ae) return json({ error: 'Could not add the cards: ' + ae.message }, 500);
    }
    await db.from('tcg_held_drops').update({ status: approve ? 'approved' : 'rejected', reviewed_by: uid, reviewed_at: new Date().toISOString() }).eq('id', h.id);
    return json({ ok: true });
  }

  // ---------- the code to show the balance in game ----------
  if (body.action === 'code') {
    const { data: a } = await db.from('tcg_accounts').select('points, lifetime, last_t').eq('user_id', uid).maybeSingle();
    // v3 also carries the cards you own and your decks, by Hearthstone card number (dbf) in base 36:
    //   HTCG3:<points>:<lifetime>:<last kill time>:<cards>:<decks>:<check>
    //   cards: <dbf>[*<count>][!<holo count>] joined by ","     decks: <name>~<hero dbf>~<dbf>.<dbf>... joined by ";"
    const [{ data: cat }, { data: own }, { data: decks }] = await Promise.all([
      db.from('tcg_cards').select('id, dbf').range(0, 9999),
      db.from('tcg_collection').select('card_id, count, holo').eq('user_id', uid).range(0, 9999),
      db.from('tcg_decks').select('name, hero_id, cards').eq('user_id', uid).order('updated_at', { ascending: false }),
    ]);
    const dbf = new Map((cat || []).map((c: { id: string; dbf: number | null }) => [c.id, c.dbf]));
    const b36 = (n: number) => n.toString(36);
    const cards = (own || []).filter((o: { card_id: string; count: number }) => o.count > 0 && dbf.get(o.card_id))
      .map((o: { card_id: string; count: number; holo: number }) => b36(dbf.get(o.card_id)!) + (o.count > 1 ? '*' + b36(o.count) : '') + (o.holo > 0 ? '!' + b36(o.holo) : '')).join(',');
    const deckStr = (decks || []).map((d: { name: string; hero_id: string; cards: string[] }) =>
      [d.name.replace(/[^\w '\-!?.&]/g, '').slice(0, 30), b36(dbf.get(d.hero_id) || 0), (d.cards || []).map(id => b36(dbf.get(id) || 0)).join('.')].join('~')).join(';');
    return json({ ok: true, code: collectionCode(a?.points || 0, a?.lifetime || 0, a?.last_t || 0, cards, deckStr) });
  }

  if (body.action !== 'sync') return json({ error: 'Unknown action' }, 400);
  const lines: string[] = Array.isArray(body.entries) ? body.entries.filter((x: unknown) => typeof x === 'string').slice(-MAX_ENTRIES) : [];

  const { data: acct0 } = await db.from('tcg_accounts').select('*').eq('user_id', uid).maybeSingle();
  if (acct0?.banned) return json({ error: 'Your TCG account is suspended. Talk to the Raid Leader.' }, 403);
  const lastT = acct0?.last_t || 0;

  const now = Math.floor(Date.now() / 1000);
  type E = { kind: string; t: number; char: string; plvl: number; id: number; guid: string; lvl: number; cls: string; raid: boolean; bossKey: string; srv?: number; map?: number;
    ctype: string; fac: string; dkey: string; inst: number; first?: boolean; grey?: boolean; grp?: string; ncls?: string };
  const items: E[] = [];
  const flags: string[] = [];
  if (body.tampered) flags.push('The log was edited outside the game (its seal does not match).');
  const inBatch = new Set<string>();
  for (const line of lines) {
    const f = line.split(',');
    const t = +f[1];
    if (!t || t <= lastT || t < TCG_START || t < now - MAX_AGE || t > now + 300) continue;
    if (f[0] === 'm' && f.length >= 10) {
      if (f[5]) { if (inBatch.has(f[5])) continue; inBatch.add(f[5]); }
      items.push({ kind: 'm', t, char: f[2], plvl: +f[3] || 0, id: +f[4], guid: f[5], lvl: +f[8] || 0, cls: f[9], raid: false, bossKey: '',
        ctype: /^[A-Z]$/.test(f[12] || '') ? f[12] : '', fac: /^[HA]$/.test(f[13] || '') ? f[13] : '', dkey: '', inst: +f[6] || 0,
        grp: f.length >= 16 ? f[14] : undefined, ncls: f.length >= 16 ? f[15] : undefined });
    } else if (f[0] === 'b' && f.length >= 10) {
      const raid = f[5] === 'r';
      // a raid boss counts once per character per lockout week; a dungeon boss once per character per hour
      const bucket = raid ? Math.floor((t - 4 * 86400) / (7 * 86400)) : Math.floor(t / 3600);
      items.push({ kind: 'b', t, char: f[2], plvl: +f[3] || 0, id: +f[4], guid: '', lvl: 0, cls: '', raid, bossKey: `b:${f[4]}:${f[2]}:${bucket}`,
        ctype: '', fac: /^[HA]$/.test(f[13] || '') ? f[13] : '', dkey: /^[a-z]{1,10}$/.test(f[12] || '') ? f[12] : '', inst: +f[6] || 0,
        grp: f.length >= 16 ? f[14] : undefined, ncls: f.length >= 16 ? f[15] : undefined });
    }
  }
  items.sort((a, b) => a.t - b.t);

  // boss lockouts already used
  const bossKeys = [...new Set(items.filter(i => i.kind === 'b').map(i => i.bossKey))];
  const used = new Set<string>();
  if (bossKeys.length) {
    const { data } = await db.from('tcg_seen').select('key').eq('user_id', uid).in('key', bossKeys);
    (data || []).forEach((r: { key: string }) => used.add(r.key));
  }
  const fresh = items.filter(i => i.kind === 'm' || (!used.has(i.bossKey) && (used.add(i.bossKey), true)));

  // suspicion checks
  const perMin = new Map<number, number>(), perDay = new Map<string, number>();
  for (const i of fresh) if (i.kind === 'm') {
    perMin.set(Math.floor(i.t / 60), (perMin.get(Math.floor(i.t / 60)) || 0) + 1);
    perDay.set(dayOf(i.t), (perDay.get(dayOf(i.t)) || 0) + 1);
  }
  const busiest = Math.max(0, ...perMin.values());
  if (busiest > MAX_KILLS_PER_MINUTE) flags.push(`${busiest} kills in one minute.`);
  for (const [d, n] of perDay) if (n > MAX_KILLS_PER_DAY) flags.push(`${n} kills on ${d}.`);
  const high = fresh.filter(i => i.kind === 'm' && i.lvl > 0 && i.plvl > 0 && i.lvl > i.plvl + MAX_LEVELS_ABOVE).length;
  if (high) flags.push(`${high} kill(s) of mobs more than ${MAX_LEVELS_ABOVE} levels above the character.`);
  // ---- spawn id checks (addon 3.6+ sends each kill's spawn id: Creature-0-<server>-<instance>-<map>-<npc>-<spawn>) ----
  // A kill whose spawn id doesn't add up is DROPPED (no points, nothing held for review). Kills with no spawn id
  // (older addons, hand-made codes) still count, but only as plain kills: no first-kill or elite bonus.
  const GUID = /^(Creature|Vehicle)-0-(\d+)-(\d+)-(\d+)-(\d+)-([0-9A-F]{6,})$/;
  let rejected = 0;
  const bad = new Set<E>();
  for (const i of fresh) if (i.kind === 'm' && i.guid) {
    const g = i.guid.match(GUID);
    if (!g || +g[5] !== i.id) { bad.add(i); continue; }
    i.srv = +g[2]; i.map = +g[4];
  }
  // the account's WoW server: locked to the first one its spawn ids show, and it must be the guild's server
  const srvCount = new Map<number, number>();
  for (const i of fresh) if (i.srv != null && !bad.has(i)) srvCount.set(i.srv, (srvCount.get(i.srv) || 0) + 1);
  const { data: srvRows } = await db.from('tcg_accounts').select('wow_server').not('wow_server', 'is', null);
  const guildSrv = new Map<number, number>();
  (srvRows || []).forEach((r: { wow_server: number }) => guildSrv.set(r.wow_server, (guildSrv.get(r.wow_server) || 0) + 1));
  const guildTop = [...guildSrv.entries()].sort((a, b) => b[1] - a[1])[0];
  let accountSrv: number | null = acct0?.wow_server ?? null;
  if (accountSrv == null && srvCount.size) {
    const mine = [...srvCount.entries()].sort((a, b) => b[1] - a[1])[0][0];
    accountSrv = (guildTop && guildTop[1] >= 2) ? guildTop[0] : mine;   // a guild majority wins over a newcomer's claim
  }
  for (const i of fresh) if (i.srv != null && accountSrv != null && i.srv !== accountSrv) bad.add(i);
  // the same spawn can't be claimed twice by one account (it's remembered for ~8 days, like the other seen keys)
  const guidKeys = [...new Set(fresh.filter(i => i.srv != null && !bad.has(i)).map(i => 'g:' + i.guid))];
  const seenGuid = new Set<string>();
  for (let k = 0; k < guidKeys.length; k += 500) {
    const { data } = await db.from('tcg_seen').select('key').eq('user_id', uid).in('key', guidKeys.slice(k, k + 500));
    (data || []).forEach((r: { key: string }) => seenGuid.add(r.key));
  }
  for (const i of fresh) if (i.srv != null && seenGuid.has('g:' + i.guid)) bad.add(i);
  // where each creature lives: once 2+ other players have seen it, a kill on a map nobody else saw it on is dropped
  const npcIds = [...new Set(fresh.filter(i => i.map != null && !bad.has(i)).map(i => i.id))];
  const others = new Map<number, Map<number, Set<string>>>();
  for (let k = 0; k < npcIds.length; k += 500) {
    const { data } = await db.from('tcg_npc_maps').select('npc_id, map_id, user_id').in('npc_id', npcIds.slice(k, k + 500)).neq('user_id', uid);
    (data || []).forEach((r: { npc_id: number; map_id: number; user_id: string }) => {
      if (!others.has(r.npc_id)) others.set(r.npc_id, new Map());
      const m = others.get(r.npc_id)!; if (!m.has(r.map_id)) m.set(r.map_id, new Set()); m.get(r.map_id)!.add(r.user_id);
    });
  }
  for (const i of fresh) if (i.map != null && !bad.has(i)) {
    const maps = others.get(i.id);
    if (!maps) continue;
    const people = new Set<string>(); maps.forEach(u => u.forEach(x => people.add(x)));
    if (people.size >= 2 && !maps.has(i.map)) bad.add(i);
  }
  rejected = bad.size;
  const kept = fresh.filter(i => !bad.has(i));
  fresh.length = 0; fresh.push(...kept);

  // what's already been killed on this account
  const { data: firstRows } = await db.from('tcg_first_kills').select('key').eq('user_id', uid);
  const firsts = new Set((firstRows || []).map((r: { key: string }) => r.key));
  const { data: finals } = await db.from('tcg_final_bosses').select('encounter_id');
  const finalSet = new Set((finals || []).map((r: { encounter_id: number }) => r.encounter_id));

  let points = 0;
  const newFirsts: string[] = [];
  const summary: Record<string, number> = { firstKills: 0, repeatKills: 0, eliteKills: 0, grey: 0, dungeonBosses: 0, raidBosses: 0, rejected, unverified: 0 };
  for (const i of fresh) {
    if (i.kind === 'm') {
      if (i.lvl > 0 && i.plvl > 0 && i.lvl <= greyLevel(i.plvl)) { summary.grey++; i.grey = true; continue; }
      if (i.srv == null) { points += REPEAT; summary.repeatKills++; summary.unverified++; continue; }   // no spawn id: a plain kill
      const key = 'n:' + i.id;
      if (!firsts.has(key)) { firsts.add(key); newFirsts.push(key); points += FIRST; summary.firstKills++; i.first = true; continue; }
      if (ELITE.has(i.cls)) { points += REPEAT_ELITE; summary.eliteKills++; } else { points += REPEAT; summary.repeatKills++; }
    } else {
      const key = 'e:' + i.id;
      if (i.raid) {
        const first = !firsts.has(key);
        if (first) { firsts.add(key); newFirsts.push(key); }
        points += first ? RAID_FIRST : RAID_REPEAT; summary.raidBosses++;
      } else {
        if (!firsts.has(key)) { firsts.add(key); newFirsts.push(key); }
        points += finalSet.has(i.id) ? DUNGEON_LAST : DUNGEON_BOSS; summary.dungeonBosses++;
      }
    }
  }

  // ---- daily challenges: each character's board for each day (only kills that passed the checks above) ----
  const today = pacificDay(now);
  const dailyItems = fresh.filter(i => i.fac && (i.kind === 'm' ? (!i.grey && i.srv != null) : !i.raid) && pacificDay(i.t) > today - DAILY_CLAIM_DAYS);
  summary.dailies = 0; summary.dailyPoints = 0;
  const dailyRows: Record<string, unknown>[] = [];
  if (dailyItems.length) {
    const chars = [...new Set(dailyItems.map(i => i.char))];
    const { data: have } = await db.from('tcg_daily').select('*').eq('user_id', uid).in('char', chars).gt('day', today - DAILY_CLAIM_DAYS);
    const rows = new Map<string, { char: string; day: number; level: number; fac: string; prog: Prog; done: string[]; points: number }>();
    (have || []).forEach((r: any) => rows.set(r.char + '|' + r.day, r));
    const touched = new Set<string>();
    for (const i of dailyItems) {
      const day = pacificDay(i.t), k = i.char + '|' + day;
      let r = rows.get(k);
      if (!r) { r = { char: i.char, day, level: i.plvl, fac: i.fac, prog: {}, done: [], points: 0 }; rows.set(k, r); }   // the board locks at the first kill
      const p = r.prog, bump = (key: string) => { p[key] = (p[key] || 0) + 1; };
      if (i.kind === 'm') {
        bump('any');
        if (i.ctype) bump('type:' + i.ctype);
        if (ELITE.has(i.cls)) bump('elite');
        if (i.cls === 'rare' || i.cls === 'rareelite') bump('rare');
        if (i.first) bump('first');
        if (i.map != null) bump('map:' + i.map);      // the instance the spawn id says it was in
      } else if (i.dkey) { bump('boss:' + i.dkey); bump('bmap:' + i.dkey + ':' + i.inst); }
      touched.add(k);
    }
    for (const k of touched) {
      const r = rows.get(k)!, b = board(r.day, r.level, r.fac), pay = (id: string, pts: number) => {
        if (r.done.includes(id)) return; r.done.push(id); r.points += pts; points += pts; summary.dailies++; summary.dailyPoints += pts;
      };
      if (b.dungeon && dungeonDone(r.prog, b.dungeon)) pay('dungeon', DAILY.dungeonPoints);
      for (const t of b.tasks) if (taskCount(r.prog, t) >= t.need) pay(t.id, t.points);
      dailyRows.push({ user_id: uid, char: r.char, day: r.day, level: r.level, fac: r.fac, prog: r.prog, done: r.done, points: r.points, updated_at: new Date().toISOString() });
    }
  }

  // ---- card drops: each kill's roll again, from its spawn id (or a boss's key) - see drops.ts ----
  summary.drops = 0; summary.dropsRejected = 0;
  type Drop = { card_id?: string; dbf: number; kill_key: string; hero: boolean; holo: boolean; npc: number; char: string; rarity: string; at: number };
  let expected = 0;
  const dropKills = fresh.filter(i => i.grp !== undefined && (i.kind === 'b' || (!i.grey && i.srv != null)));
  const drops: Drop[] = [];
  const tagRows: { npc_key: number; tag: string; user_id: string }[] = [];
  if (dropKills.length) {
    // what the other players' addons say each creature is: 2+ of them agreeing outvotes a different claim
    const npcKey = (i: E) => i.kind === 'b' ? -i.id : i.id;
    const keys = [...new Set(dropKills.map(npcKey))];
    const told = new Map<number, Map<string, Set<string>>>();
    for (let k = 0; k < keys.length; k += 500) {
      const { data } = await db.from('tcg_npc_tags').select('npc_key, tag, user_id').in('npc_key', keys.slice(k, k + 500)).neq('user_id', uid);
      (data || []).forEach((r: { npc_key: number; tag: string; user_id: string }) => {
        if (!told.has(r.npc_key)) told.set(r.npc_key, new Map());
        const m = told.get(r.npc_key)!; if (!m.has(r.tag)) m.set(r.tag, new Set()); m.get(r.tag)!.add(r.user_id);
      });
    }
    for (const i of dropKills) {
      const grp = i.grp || '', cls = i.ncls || '', tag = grp + '|' + cls, nk = npcKey(i);
      if (!validGroup(grp) || !validClass(cls)) { summary.dropsRejected++; continue; }
      const others = told.get(nk);
      if (others && !others.has(tag) && [...others.values()].some(u => u.size >= 2)) { summary.dropsRejected++; continue; }
      tagRows.push({ npc_key: nk, tag, user_id: uid });
      const key = i.kind === 'b' ? `b|${i.id}|${i.char}|${i.t}` : i.guid;
      const kind = i.kind === 'b' ? (i.raid ? 'raidboss' : 'dungeonboss') : killKind(i.cls);
      expected += expectedDrops(grp, cls, kind);
      const r = roll(key, grp, cls, kind);
      const base = { kill_key: key, npc: i.kind === 'b' ? -i.id : i.id, char: i.char, at: i.t };
      if (r.drop) drops.push({ ...base, dbf: r.drop, hero: false, holo: r.dropHolo, rarity: rarityOf(r.drop) });
      if (r.hero) drops.push({ ...base, dbf: r.hero, hero: true, holo: r.heroHolo, rarity: rarityOf(r.hero) });
    }
  }

  const held = flags.length > 0;
  const newLastT = items.reduce((m, i) => i.t > m ? i.t : m, lastT);

  // write
  const stamp = new Date().toISOString();
  const lockRows = fresh.filter(i => i.kind === 'b').map(i => ({ user_id: uid, key: i.bossKey, seen_at: stamp }));
  if (lockRows.length) await db.from('tcg_seen').upsert(lockRows, { onConflict: 'user_id,key', ignoreDuplicates: true });
  const guidRows = fresh.filter(i => i.srv != null).map(i => ({ user_id: uid, key: 'g:' + i.guid, seen_at: stamp }));
  for (let k = 0; k < guidRows.length; k += 1000) await db.from('tcg_seen').upsert(guidRows.slice(k, k + 1000), { onConflict: 'user_id,key', ignoreDuplicates: true });
  const mapRows = [...new Map(fresh.filter(i => i.map != null).map(i => [i.id + ':' + i.map, { npc_id: i.id, map_id: i.map!, user_id: uid }])).values()];
  for (let k = 0; k < mapRows.length; k += 1000) await db.from('tcg_npc_maps').upsert(mapRows.slice(k, k + 1000), { onConflict: 'npc_id,map_id,user_id', ignoreDuplicates: true });
  // the drops: into the collection (not while the sync is held for review)
  let dropped: unknown[] = [];
  const uniqTags = [...new Map(tagRows.map(r => [r.npc_key + r.tag, r])).values()];
  for (let k = 0; k < uniqTags.length; k += 1000) await db.from('tcg_npc_tags').upsert(uniqTags.slice(k, k + 1000), { onConflict: 'npc_key,tag,user_id', ignoreDuplicates: true });
  // the luck check: this account's drops so far against what its kills should have given
  const totalExpected = (acct0?.drop_expected || 0) + expected, totalActual = (acct0?.drop_actual || 0) + drops.length;
  const chance = luckChance(totalActual, totalExpected);
  const tooLucky = drops.length > 0 && totalActual >= 3 && chance < LUCK_LIMIT;
  if (drops.length && !held) {
    const { data: ids } = await db.from('tcg_cards').select('id, dbf, name').in('dbf', [...new Set(drops.map(d => d.dbf))]);
    const byDbf = new Map((ids || []).map((c: { id: string; dbf: number; name: string }) => [c.dbf, c]));
    const rows = drops.filter(d => byDbf.has(d.dbf)).map(d => ({ ...d, card_id: byDbf.get(d.dbf)!.id }));
    if (tooLucky) {
      await db.from('tcg_held_drops').insert({ user_id: uid, drops: rows, expected: totalExpected, actual: totalActual, chance });
      summary.dropsHeld = rows.length;
    } else {
      const { data: added, error: de } = await db.rpc('tcg_add_drops', { p_user: uid, p_drops: rows });
      if (de) flags.push('Card drops could not be saved: ' + de.message);
      dropped = ((added || []) as Drop[]).map(d => ({ ...d, name: byDbf.get(d.dbf)?.name }));
      summary.drops = dropped.length;
    }
  } else if (drops.length) summary.dropsHeld = drops.length;
  if (dailyRows.length) await db.from('tcg_daily').upsert(dailyRows, { onConflict: 'user_id,char,day' });
  if (newFirsts.length) {
    for (let i = 0; i < newFirsts.length; i += 1000)
      await db.from('tcg_first_kills').upsert(newFirsts.slice(i, i + 1000).map(key => ({ user_id: uid, key })), { onConflict: 'user_id,key', ignoreDuplicates: true });
  }
  const acct = acct0 || { points: 0, lifetime: 0, held: 0 };
  const next = held ? { held: acct.held + points } : { points: acct.points + points, lifetime: acct.lifetime + points };
  const final = { points: acct.points, lifetime: acct.lifetime, held: acct.held, ...next };
  await db.from('tcg_accounts').upsert({ user_id: uid, ...final, wow_server: accountSrv, last_t: newLastT, last_sync: stamp, updated_at: stamp,
    drop_expected: totalExpected, drop_actual: totalActual }, { onConflict: 'user_id' });
  await db.from('tcg_syncs').insert({ user_id: uid, entries: lines.length, counted: fresh.length, points, summary, flags, status: held ? 'held' : 'ok' });
  await db.from('tcg_seen').delete().eq('user_id', uid).lt('seen_at', new Date(Date.now() - 15 * 86400000).toISOString());

  return json({ ok: true, points, counted: fresh.length, skipped: lines.length - fresh.length, held, flags, summary, drops: dropped,
    balance: final.points, code: balanceCode(final.points, final.lifetime, newLastT) });
});
