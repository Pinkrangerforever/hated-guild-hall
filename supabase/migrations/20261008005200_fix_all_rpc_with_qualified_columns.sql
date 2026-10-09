-- Migration: Fix all RPC functions with explicit column qualification
-- Purpose: PostgreSQL requires columns to be explicitly qualified in WHERE clauses
-- Date: 2026-10-09

-- Fix check_trader_access
CREATE OR REPLACE FUNCTION check_trader_access(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  has_access BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id)
  INTO has_access;
  RETURN jsonb_build_object(
    'has_access', has_access,
    'message', CASE WHEN has_access THEN 'Access granted' ELSE 'No access' END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Fix feed_pet
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
  SET food = food - food_cost, food_spent_total = food_spent_total + food_cost
  WHERE id = v_user_id;
  UPDATE public.pets
  SET exp = exp + exp_reward
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

-- Fix pet_action
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
  SET exp = exp + exp_reward, last_pet_action_time = now_ms
  WHERE id = v_pet_id AND user_id = v_user_id
  RETURNING exp INTO new_exp;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Pet happily received attention',
    'pet_exp', new_exp
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Fix purchase_pet_egg
CREATE OR REPLACE FUNCTION purchase_pet_egg(user_id UUID, pet_type TEXT, egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  now_ms BIGINT;
  hatch_time_ms BIGINT;
  new_pet_id UUID;
  has_access BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id)
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
