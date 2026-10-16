-- Migration: Guild Bank import (from the Hated Companion addon)
-- Purpose:
--   The addon saves the guild bank's contents and a running money log in its SavedVariables file. The Raid
--   Leader imports that file on the website's Guild Bank page; import_guild_bank() stores it:
--   1) guild_bank_snapshot: the latest look at the bank (one row): tabs + items, gold, who scanned it and when.
--   2) guild_bank_money_log: every money transaction the addon has seen, one row each, keyed by the addon's own
--      id for it, so importing the same file twice (or an older one) adds nothing new. Deposits feed the
--      donation leaderboard.
--   Members can read both; only import_guild_bank() writes, and only for the protected Raid Leader account.
--   (The older guild_bank / guild_bank_items tables from an earlier attempt are left alone, unused.)
-- Date: 2026-10-15
-- Reverse: DROP FUNCTION import_guild_bank(jsonb, jsonb); DROP TABLE guild_bank_money_log, guild_bank_snapshot;

CREATE TABLE IF NOT EXISTS public.guild_bank_snapshot (
  id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  guild_name TEXT,
  realm TEXT,
  scanned_at TIMESTAMPTZ,
  scanned_by TEXT,
  money BIGINT NOT NULL DEFAULT 0,          -- copper
  tabs JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [{ index, name, icon, items: [{ slot, itemId, name, link, count, quality }] }]
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  imported_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);
ALTER TABLE public.guild_bank_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members read the guild bank" ON public.guild_bank_snapshot;
CREATE POLICY "Members read the guild bank" ON public.guild_bank_snapshot FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_bank_snapshot FROM anon, authenticated;
GRANT SELECT ON public.guild_bank_snapshot TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_bank_snapshot TO service_role;

CREATE TABLE IF NOT EXISTS public.guild_bank_money_log (
  entry_key TEXT PRIMARY KEY,               -- the addon's id for the transaction
  kind TEXT NOT NULL,                       -- deposit / withdraw / repair / withdrawForTab / buyTab / depositSummary
  character_name TEXT,
  amount BIGINT NOT NULL DEFAULT 0,         -- copper
  happened_at TIMESTAMPTZ,                  -- approximate: WoW only gives the age in hours
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS guild_bank_money_log_deposits ON public.guild_bank_money_log (kind, happened_at DESC);
ALTER TABLE public.guild_bank_money_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members read the money log" ON public.guild_bank_money_log;
CREATE POLICY "Members read the money log" ON public.guild_bank_money_log FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_bank_money_log FROM anon, authenticated;
GRANT SELECT ON public.guild_bank_money_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_bank_money_log TO service_role;

-- p_bank: the addon's bank record; p_log: its money log entries [{ id, type, name, amount, t }]
CREATE OR REPLACE FUNCTION public.import_guild_bank(p_bank JSONB, p_log JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new INTEGER := 0; v_deposits INTEGER := 0; v_gold BIGINT := 0; v_items INTEGER := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND protected) THEN RAISE EXCEPTION 'Raid Leader only'; END IF;
  IF p_bank IS NOT NULL AND jsonb_typeof(p_bank) = 'object' THEN
    INSERT INTO guild_bank_snapshot (id, guild_name, realm, scanned_at, scanned_by, money, tabs, imported_at, imported_by)
    VALUES (1, p_bank->>'guild', p_bank->>'realm', to_timestamp((p_bank->>'scannedAt')::bigint), p_bank->>'scannedBy',
            COALESCE((p_bank->>'money')::bigint, 0), COALESCE(p_bank->'tabs', '[]'::jsonb), now(), auth.uid())
    ON CONFLICT (id) DO UPDATE SET guild_name = EXCLUDED.guild_name, realm = EXCLUDED.realm, scanned_at = EXCLUDED.scanned_at,
      scanned_by = EXCLUDED.scanned_by, money = EXCLUDED.money, tabs = EXCLUDED.tabs, imported_at = now(), imported_by = auth.uid()
    -- an older file never replaces a newer scan
    WHERE guild_bank_snapshot.scanned_at IS NULL OR EXCLUDED.scanned_at >= guild_bank_snapshot.scanned_at;
    SELECT COALESCE(sum(jsonb_array_length(t->'items')), 0) INTO v_items FROM jsonb_array_elements(COALESCE(p_bank->'tabs', '[]'::jsonb)) t;
  END IF;
  IF p_log IS NOT NULL AND jsonb_typeof(p_log) = 'array' THEN
    WITH ins AS (
      INSERT INTO guild_bank_money_log (entry_key, kind, character_name, amount, happened_at)
      SELECT e->>'id', COALESCE(e->>'type', 'unknown'), e->>'name', COALESCE((e->>'amount')::bigint, 0), to_timestamp((e->>'t')::bigint)
      FROM jsonb_array_elements(p_log) e
      WHERE e->>'id' IS NOT NULL
      ON CONFLICT (entry_key) DO NOTHING
      RETURNING kind, amount
    )
    SELECT count(*), count(*) FILTER (WHERE kind = 'deposit'), COALESCE(sum(amount) FILTER (WHERE kind = 'deposit'), 0)
    INTO v_new, v_deposits, v_gold FROM ins;
  END IF;
  RETURN jsonb_build_object('new_entries', v_new, 'new_deposits', v_deposits, 'new_deposit_copper', v_gold, 'items', v_items);
END $$;
REVOKE ALL ON FUNCTION public.import_guild_bank(JSONB, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.import_guild_bank(JSONB, JSONB) TO authenticated;
