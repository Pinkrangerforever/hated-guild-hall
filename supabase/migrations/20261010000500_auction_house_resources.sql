-- Migration: The Auction House (buy Food / Wood with gold, capped per day)
-- Purpose:
--   * Two shop items in a new 'resource_bundle' category:
--       Food Bundle: 10 food for 150g, max 50 food bought per day
--       Wood Bundle: 10 wood for 60g, max 200 wood bought per day (inactive = "Coming soon"
--                    until houses exist in Phase 4)
--   * buy_resource_bundle(item): price, amount and cap come from shop_items, never the client.
--     The day resets at midnight America/Denver. Buy-only: there is no way to sell back.
--   * get_resource_purchases_today(): what the caller has bought today, for the shop counter.
-- Date: 2026-10-10
-- Reverse: DROP FUNCTION public.buy_resource_bundle(UUID);
--          DROP FUNCTION public.get_resource_purchases_today();
--          DELETE FROM public.shop_items WHERE category = 'resource_bundle';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES
  ('Food Bundle', 'Ten portions of fresh food for your pet. Each feeding uses 5 food.', 150, 'resource_bundle',
   jsonb_build_object('resource', 'food', 'amount', 10, 'daily_cap', 50), 1, true),
  ('Wood Bundle', 'Ten planks of sturdy lumber for building your house.', 60, 'resource_bundle',
   jsonb_build_object('resource', 'wood', 'amount', 10, 'daily_cap', 200, 'coming_soon', true), 2, false);

-- Amount of a resource the user has bought since midnight (America/Denver)
CREATE OR REPLACE FUNCTION public.resource_bought_today(p_user_id UUID, p_resource TEXT)
RETURNS INTEGER AS $$
  SELECT COALESCE(SUM((pl.metadata->>'amount')::INTEGER), 0)::INTEGER
  FROM public.purchase_log pl
  WHERE pl.user_id = p_user_id
    AND pl.purchase_type = p_resource || '_bundle'
    AND pl.purchased_at >= (date_trunc('day', now() AT TIME ZONE 'America/Denver') AT TIME ZONE 'America/Denver');
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.buy_resource_bundle(p_item_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_item RECORD;
  v_resource TEXT;
  v_amount INTEGER;
  v_cap INTEGER;
  v_bought_today INTEGER;
  v_gold INTEGER;
  v_new_balance INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;

  SELECT si.id, si.name, si.cost, si.active, si.metadata INTO v_item
  FROM public.shop_items si
  WHERE si.id = p_item_id AND si.category = 'resource_bundle';
  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That item is not for sale');
  END IF;
  IF NOT v_item.active THEN
    RETURN jsonb_build_object('success', false, 'error', 'Coming soon');
  END IF;

  v_resource := v_item.metadata->>'resource';
  v_amount := (v_item.metadata->>'amount')::INTEGER;
  v_cap := (v_item.metadata->>'daily_cap')::INTEGER;
  IF v_resource NOT IN ('food', 'wood') OR v_amount IS NULL OR v_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'That item is misconfigured');
  END IF;

  -- Lock the profile row first so the cap check and gold spend can't race
  SELECT pr.gold INTO v_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;

  v_bought_today := public.resource_bought_today(v_user_id, v_resource);
  IF v_cap IS NOT NULL AND v_bought_today + v_amount > v_cap THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Daily limit reached (%s/%s %s). The Auction House restocks at midnight.', v_bought_today, v_cap, v_resource),
      'bought_today', v_bought_today, 'daily_cap', v_cap);
  END IF;

  IF v_gold IS NULL OR v_gold < v_item.cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  PERFORM set_config('app.allow_purchase', 'true', true);
  IF v_resource = 'food' THEN
    UPDATE public.profiles pr
    SET gold = pr.gold - v_item.cost,
        gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost,
        food = COALESCE(pr.food, 0) + v_amount
    WHERE pr.id = v_user_id
    RETURNING pr.food INTO v_new_balance;
  ELSE
    UPDATE public.profiles pr
    SET gold = pr.gold - v_item.cost,
        gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost,
        wood = COALESCE(pr.wood, 0) + v_amount
    WHERE pr.id = v_user_id
    RETURNING pr.wood INTO v_new_balance;
  END IF;
  PERFORM set_config('app.allow_purchase', 'false', true);

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, v_resource || '_bundle', v_item.cost, v_item.name,
          jsonb_build_object('resource', v_resource, 'amount', v_amount));

  RETURN jsonb_build_object(
    'success', true,
    'resource', v_resource,
    'amount', v_amount,
    'new_gold', v_gold - v_item.cost,
    'new_balance', v_new_balance,
    'bought_today', v_bought_today + v_amount,
    'daily_cap', v_cap
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_resource_purchases_today()
RETURNS jsonb AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN jsonb_build_object('food', 0, 'wood', 0)
    ELSE jsonb_build_object(
      'food', public.resource_bought_today(auth.uid(), 'food'),
      'wood', public.resource_bought_today(auth.uid(), 'wood'))
  END;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.resource_bought_today(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.buy_resource_bundle(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_resource_purchases_today() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buy_resource_bundle(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_resource_purchases_today() TO authenticated;
