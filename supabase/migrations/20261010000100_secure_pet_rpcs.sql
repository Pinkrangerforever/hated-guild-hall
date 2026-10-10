-- Migration: Lock down pet + trader RPCs
-- Purpose:
--   * Pet RPCs act ONLY on the logged-in user (auth.uid()), never a client-supplied id
--   * Every pet RPC verifies the caller owns the pet
--   * hatch_egg enforces the 24h hatch_time server-side
--   * purchase_pet_egg reads the price from shop_items (client-sent cost is ignored)
--   * purchase_pet_egg / pay_mysterious_trader set app.allow_purchase so the
--     protect_role_column trigger lets regular members spend gold (was officer-only)
--   * Clients can no longer INSERT/UPDATE pets directly (no free pets / free exp)
--   * Drop unused, exploitable functions (old overloads + earn/spend_resource)
-- Date: 2026-10-10
-- Signatures are unchanged, so index.html needs no changes.
-- Reverse: re-run 20261009000300 / 20261009000200 / 20261008005000 and re-create
--          the two dropped pets policies from 20261008001100.

-- ============================================================================
-- 1. Remove direct client writes to pets (all writes go through RPCs below)
-- ============================================================================
DROP POLICY IF EXISTS "Users can update own pet" ON public.pets;
DROP POLICY IF EXISTS "Authenticated can create pets" ON public.pets;

-- ============================================================================
-- 2. Drop unused functions that trust a client-supplied user id
-- ============================================================================
DROP FUNCTION IF EXISTS public.hatch_egg(UUID, UUID);
DROP FUNCTION IF EXISTS public.name_pet(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.earn_resource(UUID, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.spend_resource(UUID, TEXT, INTEGER);

-- ============================================================================
-- 3. purchase_pet_egg
-- ============================================================================
CREATE OR REPLACE FUNCTION public.purchase_pet_egg(p_user_id UUID, p_pet_type TEXT, p_egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_item RECORD;
  v_current_gold INTEGER;
  v_now_ms BIGINT;
  v_hatch_time_ms BIGINT;
  v_new_pet_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'No trader access');
  END IF;

  -- Price comes from the shop, never from the client (p_egg_cost is ignored)
  SELECT si.id, si.name, si.cost INTO v_item
  FROM public.shop_items si
  WHERE si.category = 'pet_egg'
    AND si.active = true
    AND si.metadata->>'pet_type' = p_pet_type
  ORDER BY si.sort_order
  LIMIT 1;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That egg is not for sale');
  END IF;

  -- Lock the profile row so two simultaneous purchases can't double-spend
  SELECT pr.gold INTO v_current_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_current_gold IS NULL OR v_current_gold < v_item.cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  PERFORM set_config('app.allow_purchase', 'true', true);
  UPDATE public.profiles pr
  SET gold = pr.gold - v_item.cost,
      gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
  WHERE pr.id = v_user_id;
  PERFORM set_config('app.allow_purchase', 'false', true);

  v_now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_hatch_time_ms := v_now_ms + 86400000;

  INSERT INTO public.pets (user_id, pet_type, status, hatch_time)
  VALUES (v_user_id, p_pet_type, 'egg', v_hatch_time_ms)
  RETURNING id INTO v_new_pet_id;

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'shop_item', v_item.cost, v_item.name,
          jsonb_build_object('pet_type', p_pet_type, 'pet_id', v_new_pet_id));

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', v_new_pet_id,
    'pet_type', p_pet_type,
    'status', 'egg',
    'hatch_time_ms', v_hatch_time_ms,
    'new_gold', v_current_gold - v_item.cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 4. feed_pet  (5 food -> +10 exp)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.feed_pet(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_food_cost INTEGER := 5;
  v_exp_reward INTEGER := 10;
  v_pet_status TEXT;
  v_current_food INTEGER;
  v_new_exp INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Check the pet BEFORE taking any food
  SELECT p.status INTO v_pet_status
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  FOR UPDATE;
  IF v_pet_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_pet_status = 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Eggs can''t eat yet');
  END IF;

  SELECT COALESCE(pr.food, 0) INTO v_current_food FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_current_food < v_food_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient food');
  END IF;

  UPDATE public.profiles pr
  SET food = COALESCE(pr.food, 0) - v_food_cost,
      food_spent_total = COALESCE(pr.food_spent_total, 0) + v_food_cost
  WHERE pr.id = v_user_id;

  UPDATE public.pets p
  SET exp = COALESCE(p.exp, 0) + v_exp_reward, updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  RETURNING p.exp INTO v_new_exp;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fed pet',
    'food_remaining', v_current_food - v_food_cost,
    'pet_exp', v_new_exp
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 5. pet_action  (+5 exp, 1hr cooldown)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.pet_action(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_now_ms BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_cooldown_ms BIGINT := 3600000;
  v_exp_reward INTEGER := 5;
  v_pet RECORD;
  v_new_exp INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT p.id, p.status, p.last_pet_action_time INTO v_pet
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  FOR UPDATE;
  IF v_pet.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_pet.status = 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Eggs can''t be petted yet');
  END IF;
  IF v_pet.last_pet_action_time IS NOT NULL AND (v_now_ms - v_pet.last_pet_action_time) < v_cooldown_ms THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet needs to rest (1hr cooldown)');
  END IF;

  UPDATE public.pets p
  SET exp = COALESCE(p.exp, 0) + v_exp_reward, last_pet_action_time = v_now_ms, updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  RETURNING p.exp INTO v_new_exp;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Pet happily received attention',
    'pet_exp', v_new_exp
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 6. hatch_egg  (owner only, only after hatch_time)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.hatch_egg(p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_now_ms BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_clock_grace_ms BIGINT := 60000; -- tolerate small client/server clock drift
  v_pet RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;

  SELECT p.id, p.status, p.hatch_time INTO v_pet
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  FOR UPDATE;
  IF v_pet.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_pet.status <> 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Already hatched');
  END IF;
  IF v_now_ms < v_pet.hatch_time - v_clock_grace_ms THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not ready to hatch',
                              'ms_remaining', v_pet.hatch_time - v_now_ms);
  END IF;

  UPDATE public.pets p
  SET status = 'juvenile', hatched_at = now(), updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id;

  RETURN jsonb_build_object('success', true, 'message', 'Egg hatched!', 'status', 'juvenile');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 7. name_pet  (owner only, hatched pets only)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.name_pet(p_pet_id UUID, p_name TEXT)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_name TEXT := btrim(COALESCE(p_name, ''));
  v_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF length(v_name) < 1 OR length(v_name) > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Name must be 1-30 characters');
  END IF;

  SELECT p.status INTO v_status
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id;
  IF v_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_status = 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Wait for the egg to hatch');
  END IF;

  UPDATE public.pets p
  SET name = v_name, updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id;

  RETURN jsonb_build_object('success', true, 'message', 'Pet named successfully', 'name', v_name);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 8. pay_mysterious_trader  (same logic; now works for non-officers)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_cost INTEGER := 3000;
  v_user_gold INTEGER;
BEGIN
  IF v_user_id IS NULL OR pay_mysterious_trader.user_id IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  IF EXISTS (SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;

  SELECT pr.gold INTO v_user_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;
  IF v_user_gold < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold', 'current_gold', v_user_gold, 'cost', v_cost);
  END IF;

  PERFORM set_config('app.allow_purchase', 'true', true);
  UPDATE public.profiles pr
  SET gold = pr.gold - v_cost,
      gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_cost
  WHERE pr.id = v_user_id;
  PERFORM set_config('app.allow_purchase', 'false', true);

  INSERT INTO public.mystery_trader_access (user_id, payment_amount) VALUES (v_user_id, v_cost);
  INSERT INTO public.purchase_log (user_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, 'dealer_access', v_cost, 'Unlocked Shadowy Dealer - Pet Egg Access',
          jsonb_build_object('trader_cost', v_cost, 'unlocks', 'pet_eggs', 'dealer_name', 'Shadowy Dealer'));

  RETURN jsonb_build_object('success', true, 'message', 'The trader smiles. Your secret is safe with them.',
                            'new_gold', v_user_gold - v_cost, 'eggs_unlocked', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 9. Only signed-in users may call these
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.purchase_pet_egg(UUID, TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.feed_pet(UUID, UUID)                  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.pet_action(UUID, UUID)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.hatch_egg(UUID)                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.name_pet(UUID, TEXT)                  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.pay_mysterious_trader(UUID)           FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.purchase_pet_egg(UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.feed_pet(UUID, UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.pet_action(UUID, UUID)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.hatch_egg(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.name_pet(UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_mysterious_trader(UUID)           TO authenticated;
