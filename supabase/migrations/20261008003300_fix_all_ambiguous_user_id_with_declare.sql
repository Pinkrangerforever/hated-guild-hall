-- Migration: Final fix for all ambiguous user_id references using DECLARE variables
-- Purpose: Eliminate ambiguity by capturing function parameters into variables
-- This avoids PostgreSQL's column name vs parameter name ambiguity
-- Date: 2026-10-08

-- ============================================================================
-- PET SYSTEM RPC FUNCTIONS (with DECLARE variables)
-- ============================================================================

CREATE OR REPLACE FUNCTION feed_pet(user_id UUID, pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  food_cost INTEGER := 10;
  exp_reward INTEGER := 5;
  current_food INTEGER;
  new_food INTEGER;
BEGIN
  SELECT food INTO current_food FROM public.profiles WHERE id = v_user_id;
  IF current_food < food_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient food');
  END IF;
  UPDATE public.profiles
  SET food = food - food_cost, food_spent_total = food_spent_total + food_cost, updated_at = now()
  WHERE id = v_user_id;
  UPDATE public.pets
  SET exp = exp + exp_reward, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id
  RETURNING exp INTO new_food;
  IF new_food IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fed pet',
    'food_remaining', current_food - food_cost,
    'pet_exp', new_food
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION pet_action(user_id UUID, pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  now_ms BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  cooldown_ms BIGINT := 3600000;
  exp_reward INTEGER := 3;
  pet_rec RECORD;
  new_exp INTEGER;
BEGIN
  SELECT last_pet_action_time, exp, level INTO pet_rec
  FROM public.pets
  WHERE id = v_pet_id AND user_id = v_user_id;
  IF pet_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF pet_rec.last_pet_action_time IS NOT NULL AND (now_ms - pet_rec.last_pet_action_time) < cooldown_ms THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet needs to rest (1hr cooldown)');
  END IF;
  UPDATE public.pets
  SET exp = exp + exp_reward, last_pet_action_time = now_ms, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id
  RETURNING exp INTO new_exp;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Pet happily received attention',
    'pet_exp', new_exp
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION hatch_egg(user_id UUID, pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  pet_rec RECORD;
BEGIN
  SELECT id, status, hatch_time INTO pet_rec
  FROM public.pets
  WHERE id = v_pet_id AND user_id = v_user_id;
  IF pet_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF pet_rec.status != 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an egg');
  END IF;
  IF (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT < pet_rec.hatch_time THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not ready to hatch');
  END IF;
  UPDATE public.pets
  SET status = 'juvenile', hatched_at = now(), updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Egg hatched into juvenile pet!',
    'status', 'juvenile'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION name_pet(user_id UUID, pet_id UUID, pet_name TEXT)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
BEGIN
  UPDATE public.pets
  SET name = pet_name, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'new_name', pet_name,
    'message', 'Pet renamed'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION check_trader_access(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  has_access BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = v_user_id)
  INTO has_access;
  RETURN jsonb_build_object(
    'has_access', has_access,
    'message', CASE WHEN has_access THEN 'Access granted' ELSE 'No access' END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_gold INTEGER;
  cost INTEGER := 3000;
  already_paid BOOLEAN;
BEGIN
  IF auth.uid() != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = v_user_id)
  INTO already_paid;
  IF already_paid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;
  SELECT gold INTO user_gold FROM public.profiles WHERE id = v_user_id;
  IF user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;
  IF user_gold < cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient gold',
      'current_gold', user_gold,
      'cost', cost
    );
  END IF;
  UPDATE public.profiles
  SET gold = gold - cost, gold_spent_total = gold_spent_total + cost, updated_at = now()
  WHERE id = v_user_id;
  INSERT INTO public.mystery_trader_access (user_id, payment_amount)
  VALUES (v_user_id, cost);
  INSERT INTO public.purchase_log (user_id, purchase_type, amount, description, metadata)
  VALUES (
    v_user_id,
    'dealer_access',
    cost,
    'Unlocked Shadowy Dealer - Pet Egg Access',
    jsonb_build_object(
      'trader_cost', cost,
      'unlocks', 'pet_eggs',
      'dealer_name', 'Shadowy Dealer'
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'message', 'The trader smiles. Your secret is safe with them.',
    'new_gold', user_gold - cost,
    'eggs_unlocked', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION purchase_pet_egg(user_id UUID, pet_type TEXT, egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  now_ms BIGINT;
  hatch_time_ms BIGINT;
  new_pet_id UUID;
  has_access BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = v_user_id)
  INTO has_access;
  IF NOT has_access THEN
    RETURN jsonb_build_object('success', false, 'error', 'No trader access');
  END IF;
  now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  hatch_time_ms := now_ms + 86400000;
  INSERT INTO public.pets (user_id, pet_type, status, hatch_time)
  VALUES (v_user_id, pet_type, 'egg', hatch_time_ms)
  RETURNING id INTO new_pet_id;
  RETURN jsonb_build_object(
    'success', true,
    'pet_id', new_pet_id,
    'pet_type', pet_type,
    'status', 'egg',
    'hatch_time_ms', hatch_time_ms
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- HOUSE SYSTEM RPC FUNCTIONS (with DECLARE variables)
-- ============================================================================

CREATE OR REPLACE FUNCTION initialize_house(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
BEGIN
  IF EXISTS(SELECT 1 FROM public.house WHERE user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'House already exists');
  END IF;
  INSERT INTO public.house (user_id, house_tier)
  VALUES (v_user_id, 1);
  RETURN jsonb_build_object(
    'success', true,
    'message', 'House created',
    'house_tier', 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION upgrade_house(user_id UUID, target_tier INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_house RECORD;
  user_wood INTEGER;
  upgrade_cost INTEGER;
BEGIN
  SELECT house_tier INTO user_house FROM public.house WHERE user_id = v_user_id;
  IF user_house IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'House not found');
  END IF;
  IF target_tier < 1 OR target_tier > 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid tier (1-3)');
  END IF;
  IF user_house.house_tier >= target_tier THEN
    RETURN jsonb_build_object('success', false, 'error', 'Can only upgrade to higher tier');
  END IF;
  upgrade_cost := (target_tier - user_house.house_tier) * 100;
  SELECT wood INTO user_wood FROM public.profiles WHERE id = v_user_id;
  IF user_wood < upgrade_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient wood',
      'required', upgrade_cost,
      'available', user_wood
    );
  END IF;
  UPDATE public.profiles
  SET wood = wood - upgrade_cost, wood_spent_total = wood_spent_total + upgrade_cost, updated_at = now()
  WHERE id = v_user_id;
  UPDATE public.house
  SET house_tier = target_tier, updated_at = now()
  WHERE user_id = v_user_id;
  RETURN jsonb_build_object(
    'success', true,
    'new_tier', target_tier,
    'new_wood', user_wood - upgrade_cost,
    'cost', upgrade_cost,
    'message', format('House upgraded to Tier %s', target_tier)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION select_backdrop(user_id UUID, backdrop_item_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_backdrop_item_id UUID := backdrop_item_id;
BEGIN
  UPDATE public.house
  SET backdrop_id = v_backdrop_item_id, updated_at = now()
  WHERE user_id = v_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'House not found');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'backdrop_id', v_backdrop_item_id,
    'message', 'Backdrop changed'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION add_house_addition(user_id UUID, addition_item_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_addition_item_id UUID := addition_item_id;
  is_valid_addition BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.shop_items
    WHERE id = v_addition_item_id
    AND category = 'house_addition'
  ) INTO is_valid_addition;
  IF NOT is_valid_addition THEN
    RETURN jsonb_build_object('success', false, 'error', 'Addition not found or invalid');
  END IF;
  IF EXISTS(SELECT 1 FROM public.house_additions WHERE user_id = v_user_id AND addition_item_id = v_addition_item_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already own this addition');
  END IF;
  INSERT INTO public.house_additions (user_id, addition_item_id, is_active)
  VALUES (v_user_id, v_addition_item_id, true);
  RETURN jsonb_build_object(
    'success', true,
    'addition_id', v_addition_item_id,
    'is_active', true,
    'message', 'Addition added to house'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION toggle_house_addition(user_id UUID, addition_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_addition_id UUID := addition_id;
  current_active BOOLEAN;
  new_active BOOLEAN;
BEGIN
  SELECT is_active INTO current_active FROM public.house_additions
  WHERE id = v_addition_id AND user_id = v_user_id;
  IF current_active IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Addition not found');
  END IF;
  new_active := NOT current_active;
  UPDATE public.house_additions
  SET is_active = new_active, updated_at = now()
  WHERE id = v_addition_id AND user_id = v_user_id;
  RETURN jsonb_build_object(
    'success', true,
    'addition_id', v_addition_id,
    'is_active', new_active,
    'message', CASE WHEN new_active THEN 'Addition activated' ELSE 'Addition deactivated' END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION get_house_data(fetch_user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_fetch_user_id UUID := fetch_user_id;
  house_data RECORD;
BEGIN
  SELECT * INTO house_data FROM public.house WHERE user_id = v_fetch_user_id;
  IF house_data IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'House not found');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'house_tier', house_data.house_tier,
    'backdrop_id', house_data.backdrop_id,
    'updated_at', house_data.updated_at
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
