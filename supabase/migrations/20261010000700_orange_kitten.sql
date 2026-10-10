-- Migration: Orange Kitten (cat pets start as juveniles, no egg)
-- Purpose:
--   * Shop item "Orange Kitten" (pet_egg category, metadata.starts_as = 'juvenile')
--   * purchase_pet_egg: items with starts_as = 'juvenile' create an already-hatched pet
--     (status juvenile, hatched now). Everything else is unchanged from 20261010000200.
-- Date: 2026-10-10
-- Reverse: DELETE FROM public.shop_items WHERE name = 'Orange Kitten';
--          and re-run purchase_pet_egg from 20261010000200.

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES (
  'Orange Kitten',
  'A tiny orange tiger cub, smuggled in by the Shadowy Dealer. Ready to raise right away - no egg, no wait.',
  2000,
  'pet_egg',
  jsonb_build_object('pet_type', 'cat', 'starts_as', 'juvenile'),
  3,
  true
);

CREATE OR REPLACE FUNCTION public.purchase_pet_egg(p_user_id UUID, p_pet_type TEXT, p_egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_max_pets INTEGER := 3;
  v_item RECORD;
  v_current_gold INTEGER;
  v_pet_count INTEGER;
  v_now_ms BIGINT;
  v_hatch_time_ms BIGINT;
  v_status TEXT;
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

  SELECT si.id, si.name, si.cost, si.metadata INTO v_item
  FROM public.shop_items si
  WHERE si.category = 'pet_egg'
    AND si.active = true
    AND si.metadata->>'pet_type' = p_pet_type
  ORDER BY si.sort_order
  LIMIT 1;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That pet is not for sale');
  END IF;

  -- Lock the profile row first so the pet-count check and gold spend can't race
  SELECT pr.gold INTO v_current_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;

  SELECT count(*) INTO v_pet_count FROM public.pets p WHERE p.user_id = v_user_id;
  IF v_pet_count >= v_max_pets THEN
    RETURN jsonb_build_object('success', false, 'error', format('You can own up to %s pets', v_max_pets));
  END IF;

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
  IF v_item.metadata->>'starts_as' = 'juvenile' THEN
    v_status := 'juvenile';           -- no egg: ready immediately
    v_hatch_time_ms := v_now_ms;
    INSERT INTO public.pets (user_id, pet_type, status, hatch_time, hatched_at)
    VALUES (v_user_id, p_pet_type, v_status, v_hatch_time_ms, now())
    RETURNING id INTO v_new_pet_id;
  ELSE
    v_status := 'egg';
    v_hatch_time_ms := v_now_ms + 86400000;
    INSERT INTO public.pets (user_id, pet_type, status, hatch_time)
    VALUES (v_user_id, p_pet_type, v_status, v_hatch_time_ms)
    RETURNING id INTO v_new_pet_id;
  END IF;

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'shop_item', v_item.cost, v_item.name,
          jsonb_build_object('pet_type', p_pet_type, 'pet_id', v_new_pet_id));

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', v_new_pet_id,
    'pet_type', p_pet_type,
    'status', v_status,
    'hatch_time_ms', v_hatch_time_ms,
    'new_gold', v_current_gold - v_item.cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
