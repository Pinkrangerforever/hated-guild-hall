-- Migration: Hated TCG daily challenges
-- Purpose: each character gets a daily board (a dungeon from its level bracket + 3 small tasks), picked by the addon
--          and picked again by tcg-sync from the same tables (supabase/functions/tcg-sync/daily.ts). This keeps each
--          character's progress per Pacific day, so a board can fill up across several syncs and each task pays once.
--   day    Pacific day number (days since 1970-01-01)
--   level  the character's level at its first kill that day (the board's bracket); fac 'H' / 'A'
--   prog   counters: any, elite, rare, first, type:<letter>, map:<instance>, boss:<dungeon>, bmap:<dungeon>:<instance>
--   done   task ids paid ('dungeon', 'beast', ...); points = what this board has paid
-- Date: 2026-10-23
-- Reverse: DROP TABLE public.tcg_daily;

CREATE TABLE IF NOT EXISTS public.tcg_daily (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  char       text NOT NULL,
  day        int  NOT NULL,
  level      int  NOT NULL,
  fac        text NOT NULL DEFAULT '',
  prog       jsonb NOT NULL DEFAULT '{}'::jsonb,
  done       text[] NOT NULL DEFAULT '{}',
  points     int  NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, char, day)
);
ALTER TABLE public.tcg_daily ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tcg_daily_read ON public.tcg_daily;
CREATE POLICY tcg_daily_read ON public.tcg_daily FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT SELECT ON public.tcg_daily TO authenticated;
GRANT ALL ON public.tcg_daily TO service_role;
