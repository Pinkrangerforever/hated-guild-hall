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
//
// Counting each kill once: the account remembers the newest kill time it has counted (last_t). A sync only counts
// lines newer than that, so syncing the same file again adds nothing. Raid / dungeon boss lockouts are kept as keys.
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// the rules
const FIRST = 10, REPEAT = 1, REPEAT_ELITE = 3;
const DUNGEON_BOSS = 10, DUNGEON_LAST = 20, RAID_FIRST = 100, RAID_REPEAT = 20;
const MAX_AGE = 31 * 86400;              // the addon keeps 30 days
const MAX_ENTRIES = 100000;
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

  // ---------- the code to show the balance in game ----------
  if (body.action === 'code') {
    const { data: a } = await db.from('tcg_accounts').select('points, lifetime, last_t').eq('user_id', uid).maybeSingle();
    return json({ ok: true, code: balanceCode(a?.points || 0, a?.lifetime || 0, a?.last_t || 0) });
  }

  if (body.action !== 'sync') return json({ error: 'Unknown action' }, 400);
  const lines: string[] = Array.isArray(body.entries) ? body.entries.filter((x: unknown) => typeof x === 'string').slice(-MAX_ENTRIES) : [];

  const { data: acct0 } = await db.from('tcg_accounts').select('*').eq('user_id', uid).maybeSingle();
  if (acct0?.banned) return json({ error: 'Your TCG account is suspended. Talk to the Raid Leader.' }, 403);
  const lastT = acct0?.last_t || 0;

  const now = Math.floor(Date.now() / 1000);
  type E = { kind: string; t: number; char: string; plvl: number; id: number; guid: string; lvl: number; cls: string; raid: boolean; bossKey: string };
  const items: E[] = [];
  const flags: string[] = [];
  if (body.tampered) flags.push('The log was edited outside the game (its seal does not match).');
  const inBatch = new Set<string>();
  for (const line of lines) {
    const f = line.split(',');
    const t = +f[1];
    if (!t || t <= lastT || t < now - MAX_AGE || t > now + 300) continue;
    if (f[0] === 'm' && f.length >= 10) {
      if (inBatch.has(f[5])) continue; inBatch.add(f[5]);
      items.push({ kind: 'm', t, char: f[2], plvl: +f[3] || 0, id: +f[4], guid: f[5], lvl: +f[8] || 0, cls: f[9], raid: false, bossKey: '' });
    } else if (f[0] === 'b' && f.length >= 10) {
      const raid = f[5] === 'r';
      // a raid boss counts once per character per lockout week; a dungeon boss once per character per hour
      const bucket = raid ? Math.floor((t - 4 * 86400) / (7 * 86400)) : Math.floor(t / 3600);
      items.push({ kind: 'b', t, char: f[2], plvl: +f[3] || 0, id: +f[4], guid: '', lvl: 0, cls: '', raid, bossKey: `b:${f[4]}:${f[2]}:${bucket}` });
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
  const badGuid = fresh.filter(i => i.kind === 'm' && !new RegExp(`^(Creature|Vehicle)-\\d+-\\d+-\\d+-\\d+-${i.id}-[0-9A-F]+$`).test(i.guid)).length;
  if (badGuid) flags.push(`${badGuid} kill(s) with a spawn id that doesn't match its creature.`);

  // what's already been killed on this account
  const { data: firstRows } = await db.from('tcg_first_kills').select('key').eq('user_id', uid);
  const firsts = new Set((firstRows || []).map((r: { key: string }) => r.key));
  const { data: finals } = await db.from('tcg_final_bosses').select('encounter_id');
  const finalSet = new Set((finals || []).map((r: { encounter_id: number }) => r.encounter_id));

  let points = 0;
  const newFirsts: string[] = [];
  const summary: Record<string, number> = { firstKills: 0, repeatKills: 0, eliteKills: 0, grey: 0, dungeonBosses: 0, raidBosses: 0 };
  for (const i of fresh) {
    if (i.kind === 'm') {
      if (i.lvl > 0 && i.plvl > 0 && i.lvl <= greyLevel(i.plvl)) { summary.grey++; continue; }
      const key = 'n:' + i.id;
      if (!firsts.has(key)) { firsts.add(key); newFirsts.push(key); points += FIRST; summary.firstKills++; continue; }
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
  const held = flags.length > 0;
  const newLastT = items.reduce((m, i) => i.t > m ? i.t : m, lastT);

  // write
  const stamp = new Date().toISOString();
  const lockRows = fresh.filter(i => i.kind === 'b').map(i => ({ user_id: uid, key: i.bossKey, seen_at: stamp }));
  if (lockRows.length) await db.from('tcg_seen').upsert(lockRows, { onConflict: 'user_id,key', ignoreDuplicates: true });
  if (newFirsts.length) {
    for (let i = 0; i < newFirsts.length; i += 1000)
      await db.from('tcg_first_kills').upsert(newFirsts.slice(i, i + 1000).map(key => ({ user_id: uid, key })), { onConflict: 'user_id,key', ignoreDuplicates: true });
  }
  const acct = acct0 || { points: 0, lifetime: 0, held: 0 };
  const next = held ? { held: acct.held + points } : { points: acct.points + points, lifetime: acct.lifetime + points };
  const final = { points: acct.points, lifetime: acct.lifetime, held: acct.held, ...next };
  await db.from('tcg_accounts').upsert({ user_id: uid, ...final, last_t: newLastT, last_sync: stamp, updated_at: stamp }, { onConflict: 'user_id' });
  await db.from('tcg_syncs').insert({ user_id: uid, entries: lines.length, counted: fresh.length, points, summary, flags, status: held ? 'held' : 'ok' });
  await db.from('tcg_seen').delete().eq('user_id', uid).lt('seen_at', new Date(Date.now() - 15 * 86400000).toISOString());

  return json({ ok: true, points, counted: fresh.length, skipped: lines.length - fresh.length, held, flags, summary,
    balance: final.points, code: balanceCode(final.points, final.lifetime, newLastT) });
});
