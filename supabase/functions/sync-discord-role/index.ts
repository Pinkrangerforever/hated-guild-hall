// supabase/functions/sync-discord-role/index.ts
//
// Server-side only. Checks the calling user's roles in the guild's Discord
// server using the bot token, and sets their profile role accordingly.
// This is the ONLY trusted path for setting `profiles.role` — nothing in
// the browser can fake this, since the Discord API call happens here,
// authenticated with a bot token the browser never sees.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const DISCORD_GUILD_ID = '230867986964021249';
const OFFICER_ROLE_ID = '417906974420893707';
const MEMBER_ROLE_ID = '417907393020559362';
const RAID_LEADER_ROLE_ID = '417891066948091914';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'Missing Authorization header' }, 401);
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const BOT_TOKEN = Deno.env.get('DISCORD_BOT_TOKEN');

    if (!BOT_TOKEN) {
      return json({ error: 'DISCORD_BOT_TOKEN is not configured on this function' }, 500);
    }

    // Identify the caller from their own JWT (proves who's asking).
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) {
      return json({ error: 'Invalid session' }, 401);
    }

    // Admin client (service_role) — bypasses RLS, needed to read the
    // linked Discord identity and to write the resulting role.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: adminUserData, error: adminErr } = await admin.auth.admin.getUserById(user.id);
    if (adminErr || !adminUserData?.user) {
      return json({ error: 'Could not load user identity' }, 500);
    }

    const discordIdentity = (adminUserData.user.identities || []).find(
      (i: any) => i.provider === 'discord'
    );
    const discordUserId =
      discordIdentity?.provider_id ||
      discordIdentity?.identity_data?.provider_id ||
      discordIdentity?.identity_data?.sub ||
      discordIdentity?.identity_data?.id;

    if (!discordUserId) {
      return json({ error: 'No linked Discord account found for this user' }, 400);
    }

    // Ask Discord directly (bot token — never exposed to the browser)
    // whether this person is currently in the guild, and what roles they hold.
    const discordRes = await fetch(
      `https://discord.com/api/v10/guilds/${DISCORD_GUILD_ID}/members/${discordUserId}`,
      { headers: { Authorization: `Bot ${BOT_TOKEN}` } }
    );

    let newRole = 'member'; // default: signed in, but not confirmed officer
    let isProtected = false;

    if (discordRes.status === 200) {
      const member = await discordRes.json();
      const roles: string[] = member.roles || [];
      if (roles.includes(RAID_LEADER_ROLE_ID)) {
        newRole = 'officer';
        isProtected = true; // Raid Leader: cannot be demoted by anyone but this sync process
      } else if (roles.includes(OFFICER_ROLE_ID)) {
        newRole = 'officer';
      } else if (roles.includes(MEMBER_ROLE_ID)) {
        newRole = 'member';
      } else {
        newRole = 'member'; // in the guild, but no explicit role tier set
      }
    } else if (discordRes.status === 404) {
      // Not currently in the guild at all — fall back to member rather
      // than locking them out entirely (avoids surprise lockouts if the
      // bot or guild config has an issue).
      newRole = 'member';
    } else {
      const text = await discordRes.text();
      return json({ error: 'Discord API error', detail: text, status: discordRes.status }, 502);
    }

    // Never demote the very first officer account into a dead end — always
    // allow at least one officer to exist. (Simple safeguard: if this would
    // remove the LAST officer, keep them as officer.)
    const { data: currentProfile } = await admin
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    if (currentProfile?.role === 'officer' && newRole !== 'officer') {
      const { count } = await admin
        .from('profiles')
        .select('id', { count: 'exact', head: true })
        .eq('role', 'officer');
      if ((count ?? 0) <= 1) {
        newRole = 'officer'; // would have been the last officer — keep them
      }
    }

    const { error: updateErr } = await admin.rpc('set_profile_role_from_sync', {
      p_user_id: user.id,
      p_role: newRole,
      p_protected: isProtected,
    });

    if (updateErr) {
      return json({ error: 'Failed to save role', detail: updateErr.message }, 500);
    }

    const { data: updated } = await admin.from('profiles').select('*').eq('id', user.id).single();

    return json({ role: newRole, protected: isProtected, profile: updated }, 200);
  } catch (e) {
    return json({ error: 'Unexpected error', detail: String(e) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
