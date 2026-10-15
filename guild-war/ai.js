/* Guild War AI + stats, shared by the war room (browser) and the war server (Edge Function).
   botTurn(E, G, pid): a simple aggressive bot plays one turn for player pid; returns the log entries.
   playerStats(G, log): each player's captures / kills / builds / fortifies and personal score, from the battle log. */
(function(root){
function botTurn(E, G, pid){
  const p = G.players[pid]; if(!p) return;
  const f = p.faction, entries = [];
  const frontier = () => E.zonesOf(G, f).filter(k => [...E.ADJ[k]].some(n => G.zones[n].owner !== f));
  // deploy everything on the frontier zone with the juiciest target next door
  if(p.reinforce > 0){
    const spots = E.deployable(G, f).filter(k => frontier().includes(k));
    const pick = (spots.length ? spots : E.deployable(G, f)).sort((a, b) => weakest(E, G, b, f).score - weakest(E, G, a, f).score)[0];
    if(pick){ const r = E.deploy(G, pid, pick, p.reinforce); if(r.ok) entries.push(r.entry); }
  }
  const apLeft = () => G.settings.unlimitedAP || p.ap >= 1;
  // 1) attacks: any ready stack that outnumbers its target goes for it, strongest odds first
  for(let guard = 0; guard < 12 && apLeft(); guard++){
    let best = null;
    E.zonesOf(G, f).forEach(k => {
      const z = G.zones[k], can = Math.min(z.ready, z.ready + z.fresh - 1); if(can < 2) return;
      [...E.ADJ[k]].forEach(n => { const t = G.zones[n]; if(t.owner === f) return; const def = t.ready + t.fresh; const sc = can - def * 1.1 + (t.owner !== 'neutral' ? 0.5 : 0); if(sc > 0 && (!best || sc > best.sc)) best = { from: k, to: n, n: can, sc }; });
    });
    if(!best) break;
    const r = E.attack(G, pid, best.from, best.to, best.n, { warcry: p.cards.warcry > 0 });
    if(!r.ok) break; entries.push(r.entry);
  }
  // 2) march ready troops from quiet inland zones up to the most threatened front
  for(let guard = 0; guard < 4 && apLeft(); guard++){
    const fr = frontier();
    const src = E.zonesOf(G, f).filter(k => !fr.includes(k) && G.zones[k].ready >= 2 && G.zones[k].movedDay !== E.day(G)).sort((a, b) => G.zones[b].ready - G.zones[a].ready)[0];
    if(!src) break;
    const dests = fr.slice().sort((a, b) => E.threat(G, b) - E.threat(G, a));
    let moved = false;
    for(const d of dests){ const r = E.move(G, pid, src, d, G.zones[src].ready - (G.zones[src].fresh ? 0 : 1)); if(r.ok){ entries.push(r.entry); moved = true; break; } }
    if(!moved) break;
  }
  // 3) build with whatever resources they have
  ['stronghold', 'outpost'].forEach(kind => { if(!apLeft()) return; const z = frontier().concat(E.zonesOf(G, f)).find(k => G.zones[k].outpost === (kind === 'outpost' ? 0 : 1)); if(z){ const r = E.build(G, pid, z, kind); if(r.ok) entries.push(r.entry); } });
  // 4) whatever AP is left fortifies the most threatened zones that aren't fortified yet
  const forts = frontier().concat(E.zonesOf(G, f)).filter((k, i, a) => a.indexOf(k) === i && !(G.zones[k].fortifyUntil > G.clock)).sort((a, b) => E.threat(G, b) - E.threat(G, a));
  for(const k of forts){ if(G.settings.unlimitedAP || p.ap < 1) break; const r = E.fortify(G, pid, k); if(r.ok) entries.push(r.entry); }
  return entries;
}
function weakest(E, G, k, f){ let s = 0; E.ADJ[k].forEach(n => { const t = G.zones[n]; if(t.owner !== f) s = Math.max(s, 10 - (t.ready + t.fresh)); }); return { score: s }; }
function playerStats(G, log){
  const st = {};
  Object.values(G.players).forEach(p => { st[p.id] = { p, caps: 0, kills: 0, builds: 0, forts: 0, score: 0 }; });
  (log || G.log || []).forEach(e => {
    const s = st[e.pid]; if(!s) return;
    if(e.type === 'attack'){ s.kills += e.defLost || 0; if(e.captured) s.caps++; }
    else if(e.type === 'build'){ s.builds++; s.score += e.kind === 'stronghold' ? 6 : 3; }
    else if(e.type === 'fortify'){ s.forts++; s.score += 1; }
  });
  Object.values(st).forEach(s => { s.score += s.caps * 5 + s.kills; });
  return st;
}
  const api = { botTurn, playerStats };
  if(typeof module !== 'undefined') module.exports = api; else root.WarAI = api;
})(typeof window !== 'undefined' ? window : globalThis);
