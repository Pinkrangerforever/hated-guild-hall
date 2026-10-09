-- Migration: Standardize pet RPC function parameter names
-- Purpose: Use consistent p_ prefixes for all RPC parameters
-- Date: 2026-10-09

-- Fix feed_pet with p_ prefixes
DROP FUNCTION IF EXISTS public.feed_pet(UUID, UUID);
CREATE FUNCTION public.feed_pet(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := p_user_id;
  v_pet_id UUID := p_pet_id;
  food_cost INTEGER := 5;
  exp_reward INTEGER := 10;
  current_food INTEGER;
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
  WHERE id = v_pet_id AND user_id = v_user_id;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fed pet',
    'food_remaining', current_food - food_cost,
    'pet_exp', (SELECT exp FROM public.pets WHERE id = v_pet_id AND user_id = v_user_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Fix pet_action with p_ prefixes
DROP FUNCTION IF EXISTS public.pet_action(UUID, UUID);
CREATE FUNCTION public.pet_action(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := p_user_id;
  v_pet_id UUID := p_pet_id;
  now_ms BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  cooldown_ms BIGINT := 3600000;
  exp_reward INTEGER := 5;
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

-- Fix hatch_egg with p_ prefixes
DROP FUNCTION IF EXISTS public.hatch_egg(UUID);
CREATE FUNCTION public.hatch_egg(p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_pet_id UUID := p_pet_id;
BEGIN
  UPDATE public.pets
  SET status = 'juvenile'
  WHERE id = v_pet_id;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Egg hatched!'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Fix name_pet with p_ prefixes
DROP FUNCTION IF EXISTS public.name_pet(UUID, TEXT);
CREATE FUNCTION public.name_pet(p_pet_id UUID, p_name TEXT)
RETURNS jsonb AS $$
DECLARE
  v_pet_id UUID := p_pet_id;
  v_name TEXT := p_name;
BEGIN
  IF length(v_name) < 1 OR length(v_name) > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Name must be 1-30 characters');
  END IF;
  UPDATE public.pets
  SET name = v_name
  WHERE id = v_pet_id;
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Pet named successfully'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
