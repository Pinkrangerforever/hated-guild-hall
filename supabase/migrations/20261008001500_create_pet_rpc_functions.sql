-- Migration: Create RPC functions for pet system
-- Purpose: Server-side validation for all pet mechanics to prevent cheating
-- Date: 2026-10-07
-- Fixed: Use DECLARE variables to eliminate ambiguous column references

-- ============================================================================
-- RESOURCE MANAGEMENT FUNCTIONS
-- ============================================================================

-- Spend any resource (food, wood, etc) with validation
CREATE OR REPLACE FUNCTION spend_resource(
  user_id UUID,
  resource_type TEXT,
  amount INTEGER
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  current_balance INTEGER;
  new_balance INTEGER;
  spent_total_col TEXT;
BEGIN
  -- Validate resource type
  IF resource_type NOT IN ('food', 'wood') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid resource type');
  END IF;

  -- Get current balance dynamically
  EXECUTE format('SELECT %I FROM public.profiles WHERE id = $1', resource_type)
  USING v_user_id INTO current_balance;

  -- Check if user exists
  IF current_balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate sufficient balance
  IF current_balance < amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', format('Insufficient %s. Have %s, need %s', resource_type, current_balance, amount),
      'current_balance', current_balance
    );
  END IF;

  -- Calculate new balance and update both current and spent_total
  new_balance := current_balance - amount;

  -- Determine spent_total column name
  spent_total_col := resource_type || '_spent_total';

  -- Update both columns
  UPDATE public.profiles
  SET
    updated_at = now()
  WHERE id = v_user_id;

  -- Use dynamic SQL to update the resource columns
  EXECUTE format(
    'UPDATE public.profiles SET %I = %I - $2, %I = %I + $2 WHERE id = $1',
    resource_type, resource_type, spent_total_col, spent_total_col
  ) USING v_user_id, amount;

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', new_balance,
    'amount_spent', amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Earn any resource (food, wood, etc)
CREATE OR REPLACE FUNCTION earn_resource(
  user_id UUID,
  resource_type TEXT,
  amount INTEGER
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  new_balance INTEGER;
  earned_total_col TEXT;
BEGIN
  -- Validate resource type
  IF resource_type NOT IN ('food', 'wood') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid resource type');
  END IF;

  -- Determine earned_total column name
  earned_total_col := resource_type || '_earned_total';

  -- Update both current and earned_total
  EXECUTE format(
    'UPDATE public.profiles SET %I = %I + $2, %I = %I + $2, updated_at = now() WHERE id = $1 RETURNING %I',
    resource_type, resource_type, earned_total_col, earned_total_col, resource_type
  ) USING v_user_id, amount INTO new_balance;

  IF new_balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', new_balance,
    'amount_earned', amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- PET MECHANICS FUNCTIONS
-- ============================================================================

-- Feed pet: Validate food balance, deduct food, award exp
CREATE OR REPLACE FUNCTION feed_pet(
  user_id UUID,
  pet_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  user_food INTEGER;
  pet_level INTEGER;
  new_exp INTEGER;
  food_cost INTEGER := 1;
  exp_reward INTEGER := 5;
BEGIN
  -- Get user's food balance
  SELECT food INTO user_food FROM public.profiles WHERE id = v_user_id;

  IF user_food IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate food balance
  IF user_food < food_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient food',
      'current_food', user_food
    );
  END IF;

  -- Deduct food
  UPDATE public.profiles
  SET food = food - food_cost, food_spent_total = food_spent_total + food_cost, updated_at = now()
  WHERE id = v_user_id;

  -- Award exp to pet
  UPDATE public.pets
  SET exp = exp + exp_reward, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id
  RETURNING exp INTO new_exp;

  IF new_exp IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_food', user_food - food_cost,
    'new_exp', new_exp,
    'exp_awarded', exp_reward
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Pet action (petting): Validate 1hr cooldown, award exp
CREATE OR REPLACE FUNCTION pet_action(
  user_id UUID,
  pet_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  pet_rec RECORD;
  now_ms BIGINT;
  last_action_ms BIGINT;
  cooldown_ms BIGINT := 3600000;
  new_exp INTEGER;
  exp_reward INTEGER := 10;
BEGIN
  now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;

  -- Get pet
  SELECT last_pet_action_time, exp, level INTO pet_rec
  FROM public.pets
  WHERE id = v_pet_id AND user_id = v_user_id;

  IF pet_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;

  -- Validate cooldown (1 hour)
  IF (now_ms - pet_rec.last_pet_action_time) < cooldown_ms THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Pet action on cooldown',
      'cooldown_remaining_ms', cooldown_ms - (now_ms - pet_rec.last_pet_action_time),
      'last_action_time', pet_rec.last_pet_action_time
    );
  END IF;

  -- Award exp and update cooldown
  UPDATE public.pets
  SET exp = exp + exp_reward, last_pet_action_time = now_ms, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id
  RETURNING exp INTO new_exp;

  RETURN jsonb_build_object(
    'success', true,
    'new_exp', new_exp,
    'exp_awarded', exp_reward,
    'next_action_available_ms', now_ms + cooldown_ms
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Hatch egg: Validate 24hr has passed
CREATE OR REPLACE FUNCTION hatch_egg(
  user_id UUID,
  pet_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
  pet_rec RECORD;
  now_ms BIGINT;
  hatch_delay_ms BIGINT := 86400000;
BEGIN
  now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;

  -- Get pet
  SELECT id, status, hatch_time INTO pet_rec
  FROM public.pets
  WHERE id = v_pet_id AND user_id = v_user_id;

  IF pet_rec IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;

  -- Check if already hatched
  IF pet_rec.status != 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet already hatched');
  END IF;

  -- Validate 24 hours have passed
  IF (now_ms - pet_rec.hatch_time) < hatch_delay_ms THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Egg not ready to hatch',
      'time_remaining_ms', hatch_delay_ms - (now_ms - pet_rec.hatch_time),
      'hatch_time', pet_rec.hatch_time
    );
  END IF;

  -- Hatch egg: Set to juvenile status and record hatch time
  UPDATE public.pets
  SET status = 'juvenile', hatched_at = now(), updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', v_pet_id,
    'new_status', 'juvenile',
    'message', 'Pet hatched! Time to name your companion.'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Update pet name
CREATE OR REPLACE FUNCTION name_pet(
  user_id UUID,
  pet_id UUID,
  pet_name TEXT
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_pet_id UUID := pet_id;
BEGIN
  -- Validate name length
  IF LENGTH(pet_name) < 1 OR LENGTH(pet_name) > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet name must be 1-30 characters');
  END IF;

  -- Update pet name
  UPDATE public.pets
  SET name = pet_name, updated_at = now()
  WHERE id = v_pet_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', v_pet_id,
    'pet_name', pet_name
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- TRADER & EGG PURCHASE FUNCTIONS
-- ============================================================================

-- Check if user has trader access
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
    'cost_to_unlock', 3000
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Pay mysterious trader: Validate gold, deduct 3000g, unlock eggs
CREATE OR REPLACE FUNCTION pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_gold INTEGER;
  cost INTEGER := 3000;
  already_paid BOOLEAN;
BEGIN
  -- Check if already paid
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = v_user_id)
  INTO already_paid;

  IF already_paid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;

  -- Get gold balance
  SELECT gold INTO user_gold FROM public.profiles WHERE id = v_user_id;

  IF user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate gold balance
  IF user_gold < cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient gold',
      'current_gold', user_gold,
      'cost', cost
    );
  END IF;

  -- Deduct gold
  UPDATE public.profiles
  SET gold = gold - cost, gold_spent_total = gold_spent_total + cost, updated_at = now()
  WHERE id = v_user_id;

  -- Record trader access
  INSERT INTO public.mystery_trader_access (user_id, payment_amount)
  VALUES (v_user_id, cost);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'The trader smiles. Your secret is safe with them.',
    'new_gold', user_gold - cost,
    'eggs_unlocked', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Purchase pet egg: Deduct gold, create egg with 24hr hatch timer
CREATE OR REPLACE FUNCTION purchase_pet_egg(
  user_id UUID,
  pet_type TEXT,
  egg_cost INTEGER
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_gold INTEGER;
  now_ms BIGINT;
  hatch_time_ms BIGINT;
  new_pet_id UUID;
  has_access BOOLEAN;
BEGIN
  -- Check trader access
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = v_user_id)
  INTO has_access;

  IF NOT has_access THEN
    RETURN jsonb_build_object('success', false, 'error', 'Find the mysterious trader first');
  END IF;

  -- Get gold balance
  SELECT gold INTO user_gold FROM public.profiles WHERE id = v_user_id;

  IF user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate gold balance
  IF user_gold < egg_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient gold',
      'current_gold', user_gold,
      'cost', egg_cost
    );
  END IF;

  -- Calculate hatch time (24 hours from now in milliseconds)
  now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  hatch_time_ms := now_ms + 86400000;

  -- Deduct gold
  UPDATE public.profiles
  SET gold = gold - egg_cost, gold_spent_total = gold_spent_total + egg_cost, updated_at = now()
  WHERE id = v_user_id;

  -- Create egg
  INSERT INTO public.pets (user_id, pet_type, level, exp, hatch_time, status)
  VALUES (v_user_id, pet_type, 1, 0, hatch_time_ms, 'egg')
  RETURNING id INTO new_pet_id;

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', new_pet_id,
    'pet_type', pet_type,
    'status', 'egg',
    'new_gold', user_gold - egg_cost,
    'hatch_time_ms', hatch_time_ms,
    'message', 'You received a mysterious egg. Return in 24 hours.'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
