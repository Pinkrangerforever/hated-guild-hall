-- Migration: Guild bank money log - no double counting
-- Purpose: the addon (before 3.6.1) read WoW's money log in the wrong order, so each new scan failed to line up with
--          what it had already saved and logged the same transactions again under new ids. import_guild_bank() now
--          matches entries by what they are rather than by the addon's id: for each (kind, character, amount), the
--          file adds only as many as it has beyond those already stored around the same time (WoW's log shows the
--          whole recent history, so its count of a given transaction is the true count). Also removes the
--          duplicates the first prod import created.
-- Date: 2026-10-23
-- Reverse: re-run 20261015000800's CREATE FUNCTION import_guild_bank.

-- the first prod scan's copies of transactions the next scan logged again (no-op where they don't exist)
DELETE FROM public.guild_bank_money_log WHERE entry_key IN
  ('Pink-1792123753-244781-1', 'Pink-1792123753-244781-2', 'Pink-1792123753-244781-3', 'Pink-1792123753-244781-4');

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
    WHERE guild_bank_snapshot.scanned_at IS NULL OR EXCLUDED.scanned_at >= guild_bank_snapshot.scanned_at;
    SELECT COALESCE(sum(jsonb_array_length(t->'items')), 0) INTO v_items FROM jsonb_array_elements(COALESCE(p_bank->'tabs', '[]'::jsonb)) t;
  END IF;
  IF p_log IS NOT NULL AND jsonb_typeof(p_log) = 'array' THEN
    WITH f AS (   -- the file's entries, numbered within each kind/character/amount, oldest first
      SELECT e->>'id' AS id, COALESCE(e->>'type', 'unknown') AS kind, e->>'name' AS name, COALESCE((e->>'amount')::bigint, 0) AS amount,
             to_timestamp((e->>'t')::bigint) AS t
      FROM jsonb_array_elements(p_log) e WHERE e->>'id' IS NOT NULL
    ), g AS (
      SELECT f.*, row_number() OVER (PARTITION BY kind, name, amount ORDER BY t, id) AS rn,
             min(t) OVER (PARTITION BY kind, name, amount) AS t0, max(t) OVER (PARTITION BY kind, name, amount) AS t1
      FROM f
    ), keep AS (   -- only the ones beyond what's already stored for that transaction around the same time
      SELECT g.* FROM g
      WHERE g.rn > (SELECT count(*) FROM guild_bank_money_log m
                    WHERE m.kind = g.kind AND m.character_name IS NOT DISTINCT FROM g.name AND m.amount = g.amount
                      AND m.happened_at BETWEEN g.t0 - interval '3 hours' AND g.t1 + interval '3 hours')
    ), ins AS (
      INSERT INTO guild_bank_money_log (entry_key, kind, character_name, amount, happened_at)
      SELECT id, kind, name, amount, t FROM keep
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
