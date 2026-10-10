-- Migration: Lock down profile currencies + close the purchase-flag leak
-- Purpose:
--   1) protect_role_column now runs as the caller (SECURITY INVOKER), so it can tell a direct API
--      update (role 'authenticated'/'anon') from our own SECURITY DEFINER functions (role 'postgres').
--      * Server functions (purchases, sparkle rewards, feeding, admin resets, Discord sync) are trusted.
--      * Direct API updates are always checked, and the app.allow_purchase / allow_sparkle_claim /
--        sync_in_progress flags are IGNORED for them. Those flags were set with is_local=false in some
--        gold functions, so they could stay on for the pooled connection and let a later direct
--        "update my gold" request through. That leak is now closed without touching the gold functions.
--      * New: players can no longer directly change food, wood, the earned/spent totals, or
--        discord_rank_level (these only change through server functions).
--   2) purchase_shop_item refuses pet eggs and Auction House bundles (they have their own
--      functions; buying them here took gold and granted nothing). Its purchase flag is now
--      transaction-local. Gold logic is otherwise unchanged.
--   3) House functions are disabled for players until Phase 4 rebuilds them (they trust a
--      client-supplied user id and some reference columns that don't exist).
-- Date: 2026-10-10
-- Reverse: re-create protect_role_column / purchase_shop_item from the 2026-10-10 schema backup and
--          GRANT EXECUTE on the house functions back to authenticated.

-- ============================================================================
-- 1) Profile protection trigger
-- ============================================================================
CREATE OR REPLACE FUNCTION public.protect_role_column()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
begin
  -- Our own server functions (SECURITY DEFINER, owned by postgres), migrations and the SQL editor
  -- are trusted. Only direct API requests from players are checked below.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if old.protected = true then
    if new.role is distinct from old.role or new.protected is distinct from old.protected then
      raise exception 'This account is protected and can only be changed by the Discord sync process';
    end if;
  end if;

  if new.role is distinct from old.role then
    if not public.is_officer() then
      raise exception 'Role can only be changed by an officer or the Discord sync process';
    end if;
  end if;

  if new.protected is distinct from old.protected then
    raise exception 'Protected status can only be changed by the Discord sync process';
  end if;

  if new.gold is distinct from old.gold or new.last_gold_claim_at is distinct from old.last_gold_claim_at then
    if not (public.is_officer() or (select p.discord_rank_level from public.profiles p where p.id = auth.uid()) = 1) then
      raise exception 'Gold can only be changed by the sparkle claim process or by Raid Leaders';
    end if;
  end if;

  if new.food is distinct from old.food
     or new.wood is distinct from old.wood
     or new.food_earned_total is distinct from old.food_earned_total
     or new.food_spent_total is distinct from old.food_spent_total
     or new.wood_earned_total is distinct from old.wood_earned_total
     or new.wood_spent_total is distinct from old.wood_spent_total
     or new.gold_earned_total is distinct from old.gold_earned_total
     or new.gold_spent_total is distinct from old.gold_spent_total
     or new.discord_rank_level is distinct from old.discord_rank_level then
    raise exception 'Resources, totals and rank can only be changed by the game itself';
  end if;

  return new;
end;
$$;

-- ============================================================================
-- 2) purchase_shop_item: not for eggs/bundles; transaction-local purchase flag
-- ============================================================================
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_item_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_item RECORD;
  v_gold INTEGER;
  v_new_gold INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_item FROM shop_items WHERE id = p_item_id;
  IF v_item IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'item_not_found');
  END IF;

  IF NOT v_item.active THEN
    RETURN json_build_object('success', false, 'reason', 'item_unavailable');
  END IF;

  -- Pets and Auction House bundles have their own purchase functions
  IF v_item.category IN ('pet_egg', 'resource_bundle') THEN
    RETURN json_build_object('success', false, 'reason', 'item_unavailable');
  END IF;

  SELECT gold INTO v_gold FROM profiles WHERE id = v_user_id;
  IF v_gold IS NULL OR v_gold < v_item.cost THEN
    RETURN json_build_object('success', false, 'reason', 'insufficient_gold');
  END IF;

  v_new_gold := v_gold - v_item.cost;

  PERFORM set_config('app.allow_purchase', 'true', true);

  UPDATE profiles SET gold = v_new_gold WHERE id = v_user_id;

  INSERT INTO public.gold_transactions (user_id, transaction_type, amount, reason, source)
  VALUES (v_user_id, 'spent', v_item.cost, 'Shop purchase: ' || v_item.name, 'shop');

  INSERT INTO shop_purchases (user_id, item_id, item_name, cost_paid, fulfilled)
  VALUES (v_user_id, p_item_id, v_item.name, v_item.cost, true);

  RETURN json_build_object('success', true, 'new_gold', v_new_gold, 'item_name', v_item.name);
END;
$$;

-- ============================================================================
-- 3) House functions: off for players until Phase 4
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.initialize_house(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.upgrade_house(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.select_backdrop(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.add_house_addition(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.toggle_house_addition(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_house_data(uuid) FROM PUBLIC, anon, authenticated;
