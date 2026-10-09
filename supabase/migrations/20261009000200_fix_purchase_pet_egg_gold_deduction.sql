-- Migration: Fix purchase_pet_egg to deduct gold
-- Purpose: Ensure gold is deducted when purchasing pet egg
-- Date: 2026-10-09

CREATE OR REPLACE FUNCTION public.purchase_pet_egg(p_user_id UUID, p_pet_type TEXT, p_egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := p_user_id;
  v_pet_type TEXT := p_pet_type;
  v_egg_cost INTEGER := p_egg_cost;
  now_ms BIGINT;
  hatch_time_ms BIGINT;
  new_pet_id UUID;
  has_access BOOLEAN;
  current_gold INTEGER;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id)
  INTO has_access;
  IF NOT has_access THEN
    RETURN jsonb_build_object('success', false, 'error', 'No trader access');
  END IF;

  SELECT gold INTO current_gold FROM public.profiles WHERE id = v_user_id;
  IF current_gold IS NULL OR current_gold < v_egg_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  UPDATE public.profiles
  SET gold = gold - v_egg_cost, gold_spent_total = gold_spent_total + v_egg_cost
  WHERE id = v_user_id;

  now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  hatch_time_ms := now_ms + 86400000;
  INSERT INTO public.pets (user_id, pet_type, status, hatch_time)
  VALUES (v_user_id, v_pet_type, 'egg', hatch_time_ms)
  RETURNING id INTO new_pet_id;

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', new_pet_id,
    'pet_type', v_pet_type,
    'status', 'egg',
    'hatch_time_ms', hatch_time_ms,
    'new_gold', current_gold - v_egg_cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
