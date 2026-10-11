-- Migration: Close legacy holes + unified gold ledger for the Admin page
-- Purpose:
--   SECURITY (found while reviewing the gold audit log):
--   * set_profile_role_from_sync (old Discord bot helper) was callable by anyone and could set any
--     account's role / Raid Leader flag -> execute revoked from players (the bot is gone).
--   * reset_member_current_gold / reset_member_earned_gold only checked "signed in": any player could
--     set anyone's gold -> now Raid Leader (protected) only.
--   * get_gold_transactions returned every player's earnings to anyone, even signed-out visitors
--     -> Raid Leader only.
--   * Old mini-game functions that trust the browser's "won" (complete_mini_game,
--     finalize_sparkle_event, resolve_sparkle_event_old, the 7-argument resolve_sparkle_event) and the
--     unlogged admin_reset_user_gold / reset_member_gold -> execute revoked (not dropped, so reversible).
--   * Signed-out visitors can no longer call the purchase/refund functions (they already refused them).
--   LEDGER:
--   * admin_gold_ledger(): one history of every gold/food/wood movement (mini-games, shop, pets,
--     homes, Auction House, Shadowy Dealer, house tiers, admin changes, refunds) with per-player
--     totals and a balance check (current gold vs. what the history explains).
--   * refund_shop_purchase now writes the refund into gold_transactions.
-- Date: 2026-10-11
-- Reverse: GRANT EXECUTE back on the revoked functions; restore the reset / get_gold_transactions bodies
--          from the 2026-10-10 schema backup; DROP FUNCTION admin_gold_ledger(uuid, integer, integer).

-- ============================================================================
-- 1) Revoke legacy / dangerous entry points (IF EXISTS-safe)
-- ============================================================================
DO $$
DECLARE
  f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.set_profile_role_from_sync(uuid, text, boolean)',
    'public.complete_mini_game(jsonb)',
    'public.finalize_sparkle_event(uuid, boolean, bigint, jsonb)',
    'public.resolve_sparkle_event_old(uuid, boolean, bigint, jsonb)',
    'public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb)',
    'public.admin_reset_user_gold(uuid, bigint)',
    'public.reset_member_gold(uuid, integer)'
  ] LOOP
    IF to_regprocedure(f) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    END IF;
  END LOOP;

  FOREACH f IN ARRAY ARRAY[
    'public.purchase_shop_item(uuid)', 'public.purchase_sticker(uuid, text)', 'public.purchase_rank(uuid)',
    'public.refund_shop_purchase(uuid)', 'public.reset_member_current_gold(uuid, integer)',
    'public.reset_member_earned_gold(uuid, integer)', 'public.get_gold_transactions(uuid, integer)'
  ] LOOP
    IF to_regprocedure(f) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON public.gold_transactions, public.purchase_log FROM anon, authenticated;

-- ============================================================================
-- 2) Admin gold edits: Raid Leader only, always logged
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reset_member_current_gold(p_user_id uuid, p_new_gold integer)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_old_gold INTEGER;
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = v_admin_id), false) THEN
    RETURN json_build_object('success', false, 'reason', 'forbidden');
  END IF;
  IF p_new_gold IS NULL OR p_new_gold < 0 THEN
    RETURN json_build_object('success', false, 'reason', 'invalid_amount');
  END IF;
  SELECT gold INTO v_old_gold FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF v_old_gold IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'user_not_found');
  END IF;
  UPDATE profiles SET gold = p_new_gold WHERE id = p_user_id;
  INSERT INTO gold_transactions (user_id, transaction_type, amount, reason, source, admin_user_id)
  VALUES (p_user_id, 'adjusted', p_new_gold - v_old_gold, 'Admin set current gold', 'admin_reset', v_admin_id);
  RETURN json_build_object('success', true, 'old_gold', v_old_gold, 'new_gold', p_new_gold);
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_member_earned_gold(p_user_id uuid, p_new_earned integer)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_old_earned INTEGER;
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = v_admin_id), false) THEN
    RETURN json_build_object('success', false, 'reason', 'forbidden');
  END IF;
  IF p_new_earned IS NULL OR p_new_earned < 0 THEN
    RETURN json_build_object('success', false, 'reason', 'invalid_amount');
  END IF;
  SELECT gold_earned_total INTO v_old_earned FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF v_old_earned IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'user_not_found');
  END IF;
  UPDATE profiles SET gold_earned_total = p_new_earned WHERE id = p_user_id;
  -- Leaderboard total only; current gold unchanged, so it doesn't count toward the balance check
  INSERT INTO gold_transactions (user_id, transaction_type, amount, reason, source, admin_user_id)
  VALUES (p_user_id, 'adjusted', 0, format('Admin set earned total %s -> %s', v_old_earned, p_new_earned), 'admin_reset_earned', v_admin_id);
  RETURN json_build_object('success', true, 'old_earned', v_old_earned, 'new_earned', p_new_earned);
END;
$$;

-- Kept for the old Settings view (and prod until it gets the new Admin page): Raid Leader only now
CREATE OR REPLACE FUNCTION public.get_gold_transactions(p_user_id uuid DEFAULT NULL, p_limit integer DEFAULT 500)
RETURNS TABLE(id bigint, user_id uuid, character_name text, transaction_type text, amount bigint, reason text,
              source text, admin_user_id uuid, created_at timestamp without time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT ge.id::BIGINT, ge.user_id, p.character_name, 'earned'::TEXT, ge.gold_awarded::BIGINT, ge.game_type::TEXT,
         'minigame'::TEXT, NULL::UUID, (ge.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Denver')::TIMESTAMP
  FROM game_events ge LEFT JOIN profiles p ON ge.user_id = p.id
  WHERE ge.won = TRUE AND ge.gold_awarded > 0 AND (p_user_id IS NULL OR ge.user_id = p_user_id)
  ORDER BY ge.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 2000);
END;
$$;

-- Refunds now leave a trail (otherwise unchanged)
DO $$
DECLARE
  v_def TEXT;
BEGIN
  IF to_regprocedure('public.refund_shop_purchase(uuid)') IS NULL THEN RETURN; END IF;
  v_def := pg_get_functiondef('public.refund_shop_purchase(uuid)'::regprocedure);
  IF position('gold_transactions' IN v_def) = 0 THEN
    v_def := regexp_replace(v_def,
      '(UPDATE profiles SET gold = gold \+ v_cost WHERE id = v_purchase_user_id;)',
      E'\\1\n  INSERT INTO gold_transactions (user_id, transaction_type, amount, reason, source, admin_user_id)\n  VALUES (v_purchase_user_id, ''adjusted'', v_cost, ''Shop refund'', ''refund'', v_raid_leader_id);');
    IF position('gold_transactions' IN v_def) > 0 THEN EXECUTE v_def; END IF;
  END IF;
END $$;

-- ============================================================================
-- 3) Unified ledger for the Admin page
--    Every row: when, who, currency (gold/food/wood), signed amount, kind, description.
-- ============================================================================
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
