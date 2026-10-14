-- Migration: Guild War chat (board chat + private faction chat)
-- Purpose:
--   1) guild_war_members: which faction a player is on in the current war (one row per player).
--      Until the war runs on the server, set_war_faction() fills it; for now only admins (profiles.protected)
--      may call it, since the war page is admin-only while it is being tested.
--   2) guild_war_chat: messages on three channels - 'board' (everyone), 'horde', 'alliance'.
--      Reading: board is open to every signed-in player; a faction channel only to that faction's members
--      (admins can read both). Writing only through post_war_chat(), which stamps the sender's name and
--      faction, trims the text, caps it at 300 characters and allows one message per 2 seconds.
--   3) The table is added to supabase_realtime so new messages arrive live (RLS still applies).
-- Date: 2026-10-14
-- Reverse: DROP FUNCTION post_war_chat(text, text), set_war_faction(text); DROP TABLE guild_war_chat, guild_war_members;

CREATE TABLE IF NOT EXISTS public.guild_war_members (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  faction TEXT NOT NULL CHECK (faction IN ('horde', 'alliance')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.guild_war_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players see war factions" ON public.guild_war_members;
CREATE POLICY "Players see war factions" ON public.guild_war_members FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_war_members FROM anon, authenticated;
GRANT SELECT ON public.guild_war_members TO authenticated;

CREATE TABLE IF NOT EXISTS public.guild_war_chat (
  id BIGSERIAL PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('board', 'horde', 'alliance')),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  faction TEXT CHECK (faction IN ('horde', 'alliance')),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS guild_war_chat_channel_time ON public.guild_war_chat (channel, created_at DESC);
ALTER TABLE public.guild_war_chat ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read board chat and your faction's chat" ON public.guild_war_chat;
CREATE POLICY "Read board chat and your faction's chat" ON public.guild_war_chat FOR SELECT TO authenticated USING (
  channel = 'board'
  OR EXISTS (SELECT 1 FROM public.guild_war_members m WHERE m.user_id = auth.uid() AND m.faction = guild_war_chat.channel)
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected)
);
REVOKE ALL ON public.guild_war_chat FROM anon, authenticated;
GRANT SELECT ON public.guild_war_chat TO authenticated;

-- live updates
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'guild_war_chat') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.guild_war_chat;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_war_faction(p_faction TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND protected) THEN RAISE EXCEPTION 'Only admins can change war factions while the war is in testing'; END IF;
  IF p_faction NOT IN ('horde', 'alliance') THEN RAISE EXCEPTION 'Unknown faction'; END IF;
  INSERT INTO guild_war_members (user_id, faction, updated_at) VALUES (auth.uid(), p_faction, now())
  ON CONFLICT (user_id) DO UPDATE SET faction = EXCLUDED.faction, updated_at = now();
END $$;
REVOKE ALL ON FUNCTION public.set_war_faction(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_war_faction(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.post_war_chat(p_channel TEXT, p_body TEXT)
RETURNS public.guild_war_chat LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_name TEXT; v_admin BOOLEAN; v_faction TEXT; v_body TEXT := btrim(coalesce(p_body, '')); v_row guild_war_chat;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT coalesce(nullif(character_name, ''), 'Unknown'), coalesce(protected, false) INTO v_name, v_admin FROM profiles WHERE id = auth.uid();
  IF v_name IS NULL THEN RAISE EXCEPTION 'No profile'; END IF;
  SELECT faction INTO v_faction FROM guild_war_members WHERE user_id = auth.uid();
  IF p_channel NOT IN ('board', 'horde', 'alliance') THEN RAISE EXCEPTION 'Unknown channel'; END IF;
  IF p_channel <> 'board' AND p_channel IS DISTINCT FROM v_faction THEN RAISE EXCEPTION 'You can only post in your own faction''s chat'; END IF;
  IF v_body = '' THEN RAISE EXCEPTION 'Say something first'; END IF;
  IF char_length(v_body) > 300 THEN v_body := left(v_body, 300); END IF;
  IF EXISTS (SELECT 1 FROM guild_war_chat WHERE user_id = auth.uid() AND created_at > now() - interval '2 seconds') THEN
    RAISE EXCEPTION 'Slow down a little';
  END IF;
  INSERT INTO guild_war_chat (channel, user_id, name, faction, body) VALUES (p_channel, auth.uid(), v_name, v_faction, v_body) RETURNING * INTO v_row;
  RETURN v_row;
END $$;
REVOKE ALL ON FUNCTION public.post_war_chat(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_war_chat(TEXT, TEXT) TO authenticated;
