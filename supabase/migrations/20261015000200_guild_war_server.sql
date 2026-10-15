-- Migration: Guild War on the server
-- Purpose:
--   The war moves out of each browser and onto the server. Players never write these tables: every action goes
--   through the `war` Edge Function, which checks who is signed in, runs the shared game engine and saves the result
--   with the service role (which bypasses RLS). Players can only read.
--   1) guild_war_games: one row per war. `state` is the compact game state (zones, players, settings; the battle
--      log lives in guild_war_log). `version` is bumped on every save so two actions at once can't overwrite each
--      other (the function retries on a version clash). Only one war is active at a time.
--   2) guild_war_log: every move, one row each, in order. Added to supabase_realtime so boards update live.
--   3) guild_war_medals: rewards. For now each player on the winning side gets one 'victory' medal per war.
--      Easy to wipe for a fresh start: DELETE FROM guild_war_medals; (or reset_war_medals() as an admin).
--   4) guild_war_members (from the chat migration) is now kept in sync by the server from the real teams, so
--      faction chat privacy follows the actual war.
-- Date: 2026-10-15
-- Reverse: DROP FUNCTION reset_war_medals(); DROP TABLE guild_war_medals, guild_war_log, guild_war_games;

CREATE TABLE IF NOT EXISTS public.guild_war_games (
  id TEXT PRIMARY KEY,
  state JSONB NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  week_start TIMESTAMPTZ,                 -- the war's Monday 00:00 (Pacific), set when sign-ups open
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS guild_war_games_one_active ON public.guild_war_games (active) WHERE active;
ALTER TABLE public.guild_war_games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players read wars" ON public.guild_war_games;
CREATE POLICY "Players read wars" ON public.guild_war_games FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_war_games FROM anon, authenticated;
GRANT SELECT ON public.guild_war_games TO authenticated;

CREATE TABLE IF NOT EXISTS public.guild_war_log (
  game_id TEXT NOT NULL REFERENCES public.guild_war_games(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  entry JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (game_id, seq)
);
ALTER TABLE public.guild_war_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players read the war log" ON public.guild_war_log;
CREATE POLICY "Players read the war log" ON public.guild_war_log FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_war_log FROM anon, authenticated;
GRANT SELECT ON public.guild_war_log TO authenticated;

CREATE TABLE IF NOT EXISTS public.guild_war_medals (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_id TEXT NOT NULL,
  faction TEXT NOT NULL CHECK (faction IN ('horde', 'alliance')),
  kind TEXT NOT NULL DEFAULT 'victory',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, game_id, kind)
);
ALTER TABLE public.guild_war_medals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players see medals" ON public.guild_war_medals;
CREATE POLICY "Players see medals" ON public.guild_war_medals FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_war_medals FROM anon, authenticated;
GRANT SELECT ON public.guild_war_medals TO authenticated;

-- live updates for the battle log
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'guild_war_log') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.guild_war_log;
  END IF;
END $$;

-- wipe every medal (for a fresh start once testing is done); the protected Raid Leader account only
CREATE OR REPLACE FUNCTION public.reset_war_medals()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND protected) THEN RAISE EXCEPTION 'Raid Leader only'; END IF;
  DELETE FROM guild_war_medals; GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.reset_war_medals() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_war_medals() TO authenticated;
