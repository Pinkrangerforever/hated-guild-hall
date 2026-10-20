-- Migration: Hated TCG points
-- Purpose: points earned in WoW (logged by the Hated Companion addon) toward TCG card packs. The addon only logs kills;
--          the tcg-sync Edge Function checks each sync and credits points here. Players can read their own rows;
--          officers / the Raid Leader can read everyone's (for the review queue). Only the server writes.
--   * tcg_accounts      the balance, account-wide (every character a player has adds to it)
--   * tcg_first_kills   creature / encounter keys already killed on the account ("n:<npc id>", "e:<encounter id>")
--   * tcg_seen          kills already counted (spawn ids, boss lockout keys), kept ~8 days, so a log can't count twice
--   * tcg_points_daily  repeat-kill points per day (the daily cap)
--   * tcg_syncs         one row per sync: what was credited, anything suspicious, and the officer's decision
--   * tcg_final_bosses  dungeon encounters that are the last boss (worth 20 instead of 10)
-- Date: 2026-10-19
-- Reverse: DROP TABLE public.tcg_syncs, public.tcg_points_daily, public.tcg_seen, public.tcg_first_kills, public.tcg_accounts, public.tcg_final_bosses;

CREATE TABLE IF NOT EXISTS public.tcg_accounts (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  points     int NOT NULL DEFAULT 0,
  lifetime   int NOT NULL DEFAULT 0,
  held       int NOT NULL DEFAULT 0,          -- points waiting for an officer (from flagged syncs)
  banned     boolean NOT NULL DEFAULT false,
  last_sync  timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tcg_first_kills (
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  key      text NOT NULL,
  at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);

CREATE TABLE IF NOT EXISTS public.tcg_seen (
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  key      text NOT NULL,
  seen_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);
CREATE INDEX IF NOT EXISTS tcg_seen_age ON public.tcg_seen (seen_at);

CREATE TABLE IF NOT EXISTS public.tcg_points_daily (
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day      date NOT NULL,
  repeat_points int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

CREATE TABLE IF NOT EXISTS public.tcg_syncs (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  at          timestamptz NOT NULL DEFAULT now(),
  entries     int NOT NULL DEFAULT 0,
  counted     int NOT NULL DEFAULT 0,
  points      int NOT NULL DEFAULT 0,
  summary     jsonb NOT NULL DEFAULT '{}'::jsonb,
  flags       jsonb NOT NULL DEFAULT '[]'::jsonb,
  status      text NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'held', 'approved', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz
);
CREATE INDEX IF NOT EXISTS tcg_syncs_user ON public.tcg_syncs (user_id, at DESC);
CREATE INDEX IF NOT EXISTS tcg_syncs_held ON public.tcg_syncs (status) WHERE status = 'held';

CREATE TABLE IF NOT EXISTS public.tcg_final_bosses (
  encounter_id int PRIMARY KEY,
  name         text
);

ALTER TABLE public.tcg_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_first_kills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_points_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_syncs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_final_bosses ENABLE ROW LEVEL SECURITY;

-- read: your own rows; officers / the Raid Leader read everyone's accounts and syncs
DROP POLICY IF EXISTS tcg_accounts_read ON public.tcg_accounts;
CREATE POLICY tcg_accounts_read ON public.tcg_accounts FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
DROP POLICY IF EXISTS tcg_syncs_read ON public.tcg_syncs;
CREATE POLICY tcg_syncs_read ON public.tcg_syncs FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
DROP POLICY IF EXISTS tcg_first_kills_read ON public.tcg_first_kills;
CREATE POLICY tcg_first_kills_read ON public.tcg_first_kills FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS tcg_final_bosses_read ON public.tcg_final_bosses;
CREATE POLICY tcg_final_bosses_read ON public.tcg_final_bosses FOR SELECT TO authenticated USING (true);
-- tcg_seen and tcg_points_daily: server only (no policies = no access for players)

GRANT SELECT ON public.tcg_accounts, public.tcg_syncs, public.tcg_first_kills, public.tcg_final_bosses TO authenticated;
GRANT ALL ON public.tcg_accounts, public.tcg_syncs, public.tcg_first_kills, public.tcg_seen, public.tcg_points_daily, public.tcg_final_bosses TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
