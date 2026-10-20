-- Migration: Hated TCG - count each kill once by time, Raid Leader-only review
-- Purpose: the account remembers the newest kill time it has counted (last_t); a sync only counts newer log lines.
--          That replaces remembering every kill (much smaller) and lets the addon keep 30 days of kills.
--          Other players' TCG accounts and syncs are readable by the Raid Leader only (the review queue).
-- Date: 2026-10-19
-- Reverse: ALTER TABLE public.tcg_accounts DROP COLUMN last_t; (and restore the officer policies from 20261019000100)

ALTER TABLE public.tcg_accounts ADD COLUMN IF NOT EXISTS last_t bigint NOT NULL DEFAULT 0;

DROP POLICY IF EXISTS tcg_accounts_read ON public.tcg_accounts;
CREATE POLICY tcg_accounts_read ON public.tcg_accounts FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
DROP POLICY IF EXISTS tcg_syncs_read ON public.tcg_syncs;
CREATE POLICY tcg_syncs_read ON public.tcg_syncs FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));

-- per-kill memory is no longer used for normal kills
DELETE FROM public.tcg_seen WHERE key LIKE 'g:%';
