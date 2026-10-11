-- Migration: Day 7 login bonus also gives 5 crystals
-- Date: 2026-10-11
-- Reverse: re-run daily_bonus_reward / claim_daily_bonus from 20261011000900 and admin_gold_ledger from 20261011001500.

ALTER TABLE public.daily_login_claims ADD COLUMN IF NOT EXISTS crystals INTEGER NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.daily_bonus_reward(p_cycle_day INTEGER)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'gold', CASE p_cycle_day WHEN 1 THEN 25 WHEN 2 THEN 35 WHEN 3 THEN 45 WHEN 4 THEN 55 WHEN 5 THEN 65 WHEN 6 THEN 75 ELSE 100 END,
    'food', CASE WHEN p_cycle_day = 7 THEN 10 ELSE 0 END,
    'wood', CASE WHEN p_cycle_day = 7 THEN 20 ELSE 0 END,
    'crystals', CASE WHEN p_cycle_day = 7 THEN 5 ELSE 0 END);
$$;

CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'America/Denver')::DATE;
  n RECORD;
  v_reward JSONB;
  v_gold INTEGER; v_food INTEGER; v_wood INTEGER; v_crystals INTEGER;
  v_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_authenticated'); END IF;
  PERFORM 1 FROM profiles WHERE id = v_user_id FOR UPDATE; -- one claim at a time per player
  SELECT * INTO n FROM daily_bonus_next(v_user_id);
  IF n.claimed_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_claimed', 'streak', n.streak);
  END IF;

  v_reward := daily_bonus_reward(n.cycle_day);
  v_gold := (v_reward->>'gold')::INT; v_food := (v_reward->>'food')::INT; v_wood := (v_reward->>'wood')::INT; v_crystals := COALESCE((v_reward->>'crystals')::INT, 0);
  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;
  IF v_status = 'BANNED' THEN v_gold := 0; v_food := 0; v_wood := 0; v_crystals := 0; END IF;

  INSERT INTO daily_login_claims (user_id, day, streak, cycle_day, grace_used, gold, food, wood, crystals)
  VALUES (v_user_id, v_today, n.streak, n.cycle_day, n.grace, v_gold, v_food, v_wood, v_crystals);

  UPDATE profiles SET
    gold = COALESCE(gold, 0) + v_gold, gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold,
    food = COALESCE(food, 0) + v_food, food_earned_total = COALESCE(food_earned_total, 0) + v_food,
    wood = COALESCE(wood, 0) + v_wood, wood_earned_total = COALESCE(wood_earned_total, 0) + v_wood,
    crystals = COALESCE(crystals, 0) + v_crystals, crystals_earned_total = COALESCE(crystals_earned_total, 0) + v_crystals
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true, 'streak', n.streak, 'cycle_day', n.cycle_day, 'grace', n.grace,
    'gold', v_gold, 'food', v_food, 'wood', v_wood, 'crystals', v_crystals,
    'totals', (SELECT jsonb_build_object('gold', gold, 'food', food, 'wood', wood, 'crystals', crystals) FROM profiles WHERE id = v_user_id));
END;
$$;

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
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'wood', ge.wood_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.wood_awarded > 0
    UNION ALL
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'crystals', ge.crystals_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.crystals_awarded > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'crystals', d.crystals, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.crystals > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'wood', d.wood, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.wood > 0
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
    -- Daily login bonus (gold, food, wood)
    SELECT dl.claimed_at, dl.user_id, 'gold', dl.gold, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.gold > 0
    UNION ALL
    SELECT dl.claimed_at, dl.user_id, 'food', dl.food, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.food > 0
    UNION ALL
    SELECT dl.claimed_at, dl.user_id, 'wood', dl.wood, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.wood > 0
    UNION ALL
    SELECT dl.claimed_at, dl.user_id, 'crystals', dl.crystals, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.crystals > 0
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

REVOKE EXECUTE ON FUNCTION public.claim_daily_bonus() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) TO authenticated;
