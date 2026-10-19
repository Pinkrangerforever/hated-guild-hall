// addon-release: publishes the Hated Companion addon (built by the website: addon + plan + screenshots) to CurseForge.
// Only the Raid Leader (profiles.protected) may publish. The CurseForge key never reaches the browser.
//
// Secrets (Supabase dashboard > Edge Functions > Secrets):
//   CF_API_TOKEN       CurseForge author API token (authors.curseforge.com > account > API tokens)
//   CF_PROJECT_ID      the Hated Companion project's id on CurseForge
//   CF_GAME_VERSION    optional, the game version to tag (default "1.60.1", WoW Forever)
//
// POST ?version=<text>&changelog=<text>   body: the zip   ->   { ok, fileId, version } or { error }
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const CF = 'https://wow.curseforge.com/api';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);

  // who is asking: must be the Raid Leader
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'Sign in first' }, 401);
  const { data: u, error: ue } = await createClient(URL_, ANON).auth.getUser(token);
  if (ue || !u?.user) return json({ error: 'Sign in first' }, 401);
  const db = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  const { data: prof } = await db.from('profiles').select('protected').eq('id', u.user.id).maybeSingle();
  if (!prof?.protected) return json({ error: 'Only the Raid Leader can publish the addon' }, 403);

  const cfToken = Deno.env.get('CF_API_TOKEN'), project = Deno.env.get('CF_PROJECT_ID');
  if (!cfToken || !project) return json({ error: 'CurseForge is not set up yet (CF_API_TOKEN / CF_PROJECT_ID secrets)' }, 500);
  const wanted = Deno.env.get('CF_GAME_VERSION') || '1.60.1';

  const q = new URL(req.url).searchParams;
  const version = (q.get('version') || '').slice(0, 60) || new Date().toISOString().slice(0, 16);
  const changelog = (q.get('changelog') || 'Updated boss plans.').slice(0, 2000);
  const zip = new Uint8Array(await req.arrayBuffer());
  if (zip.length < 100 || zip[0] !== 0x50 || zip[1] !== 0x4b) return json({ error: 'That is not a zip' }, 400);

  // the game version id CurseForge uses for WoW Forever
  const vr = await fetch(`${CF}/game/versions`, { headers: { 'X-Api-Token': cfToken } });
  if (!vr.ok) return json({ error: `CurseForge rejected the token (${vr.status})` }, 502);
  const versions: { id: number; name: string }[] = await vr.json();
  const ids = versions.filter(v => v.name === wanted).map(v => v.id);
  if (!ids.length) return json({ error: `CurseForge has no game version named ${wanted}` }, 502);

  const form = new FormData();
  form.append('metadata', JSON.stringify({
    changelog, changelogType: 'text', displayName: `Hated Companion ${version}`, gameVersions: ids, releaseType: 'release',
  }));
  form.append('file', new Blob([zip], { type: 'application/zip' }), `HatedCompanion-${version.replace(/[^\w.-]/g, '_')}.zip`);
  const up = await fetch(`${CF}/projects/${project}/upload-file`, { method: 'POST', headers: { 'X-Api-Token': cfToken }, body: form });
  const text = await up.text();
  if (!up.ok) return json({ error: `CurseForge upload failed (${up.status}): ${text.slice(0, 300)}` }, 502);
  let id: unknown = null; try { id = JSON.parse(text).id; } catch (_) { /* keep null */ }
  return json({ ok: true, fileId: id, version });
});
