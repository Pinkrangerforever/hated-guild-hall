-- Migration: Keep the database small - 90 days of game detail, then daily summaries
-- Purpose:
--   * game_events_daily: one row per player / day (America/Denver) / game with games, wins, gold,
--     food, fastest reaction and flagged count.
--   * rollup_old_game_events(keep_days): folds game_events older than keep_days into the daily table
--     and deletes them. Scheduled nightly with pg_cron at 10:00 UTC (3-4 AM Denver, after the
--     2 AM backup). Detailed rows the backups need are still there when the backup runs.
--   * admin_gold_ledger also counts the daily rows, so all-time totals and the balance check stay right.
--   * admin_db_stats(): database size + biggest tables for the Admin page (Raid Leader only).
--   Kept forever (small): cheat_audit_log, user_cheat_scores, gold_transactions, purchase_log.
-- Date: 2026-10-11
-- Reverse: SELECT cron.unschedule('rollup-old-game-events'); DROP FUNCTION rollup_old_game_events(integer),
--          admin_db_stats(); re-run admin_gold_ledger from 20261011000600; DROP TABLE game_events_daily
--          (only after copying it back into game_events if the detail matters).

CREATE TABLE IF NOT EXISTS public.game_events_daily (
  user_id UUID NOT NULL,
  day DATE NOT NULL,
  game_type TEXT NOT NULL,
  games INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  gold INTEGER NOT NULL DEFAULT 0,
  food INTEGER NOT NULL DEFAULT 0,
  flagged INTEGER NOT NULL DEFAULT 0,
  fastest_reaction_ms INTEGER,
  PRIMARY KEY (user_id, day, game_type)
);
ALTER TABLE public.game_events_daily ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.game_events_daily FROM anon, authenticated; -- read only through admin functions

CREATE OR REPLACE FUNCTION public.rollup_old_game_events(p_keep_days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMP := (NOW() AT TIME ZONE 'UTC') - make_interval(days => GREATEST(p_keep_days, 7));
  v_moved INTEGER;
BEGIN
  WITH old AS (
    DELETE FROM game_events ge WHERE ge.created_at < v_cutoff RETURNING ge.*
  ), agg AS (
    SELECT o.user_id, (o.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Denver')::DATE AS day, o.game_type,
           COUNT(*)::INT AS games, COUNT(*) FILTER (WHERE o.won)::INT AS wins,
           COALESCE(SUM(o.gold_awarded), 0)::INT AS gold, COALESCE(SUM(o.food_awarded), 0)::INT AS food,
           COUNT(*) FILTER (WHERE o.flags <> ARRAY[]::TEXT[])::INT AS flagged, MIN(o.reaction_ms) AS fastest
    FROM old o GROUP BY 1, 2, 3
  ), ins AS (
    INSERT INTO game_events_daily AS d (user_id, day, game_type, games, wins, gold, food, flagged, fastest_reaction_ms)
    SELECT * FROM agg
    ON CONFLICT (user_id, day, game_type) DO UPDATE SET
      games = d.games + EXCLUDED.games, wins = d.wins + EXCLUDED.wins, gold = d.gold + EXCLUDED.gold,
      food = d.food + EXCLUDED.food, flagged = d.flagged + EXCLUDED.flagged,
      fastest_reaction_ms = LEAST(d.fastest_reaction_ms, EXCLUDED.fastest_reaction_ms)
    RETURNING 1
  )
  SELECT COALESCE((SELECT SUM(games) FROM agg), 0) INTO v_moved FROM (SELECT COUNT(*) FROM ins) x;
  RETURN v_moved;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.rollup_old_game_events(INTEGER) FROM PUBLIC, anon, authenticated;

-- Nightly at 10:00 UTC
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'rollup-old-game-events';
  PERFORM cron.schedule('rollup-old-game-events', '0 10 * * *', 'SELECT public.rollup_old_game_events(90);');
END $$;

CREATE OR REPLACE FUNCTION public.admin_db_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'database_bytes', pg_database_size(current_database()),
    'limit_bytes', 500 * 1024 * 1024,
    'game_rows', (SELECT COUNT(*) FROM game_events),
    'daily_rows', (SELECT COUNT(*) FROM game_events_daily),
    'oldest_game', (SELECT MIN(created_at) FROM game_events),
    'tables', (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.bytes DESC) FROM (
       SELECT c.relname AS name, pg_total_relation_size(c.oid) AS bytes
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r'
       ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 8) t)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_db_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_db_stats() TO authenticated;

-- Ledger: same as 20261011000600 plus the daily summaries
CREATE OR REPLACE FUNCTION public.admin_gold_ledger(p_user_id uuid DEFAULT NULL, p_days integer DEFAULT 30, p_limit integer DEFAULT 1500)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := NOW() - make_interval(days => LEAST(GREATEST(p_days, 1), 365));
  v_result JSONB;
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  WITH ledger AS (
    -- Mini-games and plain sparkles (gold + food)
    SELECT ge.created_at AT TIME ZONE 'UTC' AS at, ge.user_id, 'gold'::TEXT AS currency, ge.gold_awarded::BIGINT AS amount,
           'earned'::TEXT AS kind, CASE WHEN ge.game_type = 'normal_claim' THEN 'Sparkle' ELSE 'Mini-game: ' || ge.game_type END AS description,
           ge.flags AS flags
    FROM game_events ge WHERE ge.gold_awarded > 0
    UNION ALL
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'food', ge.food_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.food_awarded > 0
    UNION ALL
    -- Older games, rolled up into one row per player / day / game (see rollup_old_game_events)
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'gold', d.gold, 'earned',
           CASE WHEN d.game_type = 'normal_claim' THEN 'Sparkles' ELSE 'Mini-game: ' || d.game_type END || format(' (%s that day)', d.games),
           ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.gold > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'food', d.food, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.food > 0
    UNION ALL
    -- Shop, stickers, ranks, admin changes, refunds
    SELECT gt.created_at, gt.user_id, 'gold',
           CASE WHEN gt.transaction_type = 'spent' THEN -ABS(gt.amount) ELSE gt.amount END,
           gt.transaction_type, COALESCE(gt.reason, gt.source, ''), ARRAY[]::TEXT[]
    FROM gold_transactions gt
    UNION ALL
    -- Pets, homes, Auction House, Shadowy Dealer (gold) and house tiers (wood)
    SELECT pl.purchased_at, pl.user_id,
           CASE WHEN pl.purchase_type = 'house_tier' THEN 'wood' ELSE 'gold' END,
           -ABS(COALESCE(pl.amount, 0))::BIGINT, 'spent', COALESCE(pl.description, pl.purchase_type), ARRAY[]::TEXT[]
    FROM purchase_log pl
    UNION ALL
    -- What Auction House bundles gave back (food / wood)
    SELECT pl.purchased_at, pl.user_id, pl.metadata->>'resource', (pl.metadata->>'amount')::BIGINT, 'earned',
           COALESCE(pl.description, 'Auction House'), ARRAY[]::TEXT[]
    FROM purchase_log pl WHERE pl.purchase_type IN ('food_bundle', 'wood_bundle') AND pl.metadata ? 'amount'
  ),
  windowed AS (
    SELECT l.* FROM ledger l
    WHERE l.at >= v_since AND (p_user_id IS NULL OR l.user_id = p_user_id)
  ),
  totals AS (
    -- All-time gold history per player, to check against their balance
    SELECT l.user_id, SUM(l.amount) FILTER (WHERE l.currency = 'gold') AS gold_net_all_time
    FROM ledger l GROUP BY l.user_id
  )
  SELECT jsonb_build_object(
    'since', v_since,
    'entries', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.at DESC) FROM (
        SELECT w.at, w.user_id, pr.character_name, w.currency, w.amount, w.kind, w.description, w.flags
        FROM windowed w LEFT JOIN profiles pr ON pr.id = w.user_id
        ORDER BY w.at DESC LIMIT LEAST(GREATEST(p_limit, 1), 5000)) e
    ), '[]'::jsonb),
    'players', COALESCE((
      SELECT jsonb_agg(to_jsonb(s) ORDER BY s.gold_earned DESC) FROM (
        SELECT pr.id AS user_id, pr.character_name, pr.gold AS current_gold, pr.food AS current_food, pr.wood AS current_wood,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'gold' AND w.amount > 0), 0) AS gold_earned,
               COALESCE(-SUM(w.amount) FILTER (WHERE w.currency = 'gold' AND w.amount < 0), 0) AS gold_spent,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'food'), 0) AS food_net,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'wood'), 0) AS wood_net,
               COUNT(w.*) AS entries,
               -- Gold the history doesn't explain (positive = more than earned; e.g. old direct DB edits)
               pr.gold - COALESCE(t.gold_net_all_time, 0) AS gold_unexplained
        FROM profiles pr
        LEFT JOIN windowed w ON w.user_id = pr.id
        LEFT JOIN totals t ON t.user_id = pr.id
        WHERE p_user_id IS NULL OR pr.id = p_user_id
        GROUP BY pr.id, pr.character_name, pr.gold, pr.food, pr.wood, t.gold_net_all_time
        HAVING COUNT(w.*) > 0 OR pr.gold <> 0) s
    ), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) TO authenticated;
