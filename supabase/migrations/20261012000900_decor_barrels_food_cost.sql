-- Migration: barrel decor + food prices
-- Purpose: purchase_decor also charges metadata.food_cost. New pieces for any home:
--          Fish Barrel 100g + 25 food, Sitting Barrel 100g + 5 wood, Standing Barrel 100g + 5 wood.
-- Date: 2026-10-12
-- Reverse: re-run purchase_decor from 20261012000500;
--          DELETE FROM shop_items WHERE metadata->>'key' IN ('fish_barrel', 'sitting_barrel', 'standing_barrel');

CREATE OR REPLACE FUNCTION public.purchase_decor(p_item_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_item RECORD;
  v_gold INTEGER;
  v_key TEXT;
  v_qty INTEGER;
  v_crystals INTEGER;
  v_by_crystal BOOLEAN;
  v_wood INTEGER;
  v_wood_cost INTEGER;
  v_food INTEGER;
  v_food_cost INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  SELECT si.id, si.name, si.cost, si.metadata INTO v_item
  FROM public.shop_items si WHERE si.id = p_item_id AND si.category = 'home_decor' AND si.active = true;
  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That piece is not for sale');
  END IF;
  IF v_item.metadata ? 'reward' THEN
    RETURN jsonb_build_object('success', false, 'error', 'This piece can only be earned');
  END IF;
  v_key := v_item.metadata->>'key';
  v_by_crystal := COALESCE(v_item.metadata->>'currency', 'gold') = 'crystals';
  v_wood_cost := COALESCE((v_item.metadata->>'wood_cost')::INT, 0);
  v_food_cost := COALESCE((v_item.metadata->>'food_cost')::INT, 0);
  SELECT pr.gold, COALESCE(pr.crystals, 0), COALESCE(pr.wood, 0), COALESCE(pr.food, 0) INTO v_gold, v_crystals, v_wood, v_food
  FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_food < v_food_cost THEN
    RETURN jsonb_build_object('success', false, 'error', format('You need %s food', v_food_cost));
  END IF;
  IF v_wood < v_wood_cost THEN
    RETURN jsonb_build_object('success', false, 'error', format('You need %s wood', v_wood_cost));
  END IF;
  IF v_by_crystal THEN
    -- rare pieces: crystals only
    IF v_crystals < v_item.cost THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not enough crystals');
    END IF;
    UPDATE public.profiles pr SET crystals = COALESCE(pr.crystals, 0) - v_item.cost WHERE pr.id = v_user_id;
  ELSE
    IF v_gold IS NULL OR v_gold < v_item.cost THEN
      RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
    END IF;
    UPDATE public.profiles pr
    SET gold = pr.gold - v_item.cost, gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
    WHERE pr.id = v_user_id;
  END IF;
  IF v_food_cost > 0 THEN
    UPDATE public.profiles pr SET food = COALESCE(pr.food, 0) - v_food_cost WHERE pr.id = v_user_id;
  END IF;
  IF v_wood_cost > 0 THEN
    UPDATE public.profiles pr SET wood = COALESCE(pr.wood, 0) - v_wood_cost, wood_spent_total = COALESCE(pr.wood_spent_total, 0) + v_wood_cost
    WHERE pr.id = v_user_id;
  END IF;
  INSERT INTO public.player_decor (user_id, item_key, qty) VALUES (v_user_id, v_key, 1)
  ON CONFLICT (user_id, item_key) DO UPDATE SET qty = public.player_decor.qty + 1
  RETURNING qty INTO v_qty;
  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'home_decor', v_item.cost, v_item.name, jsonb_build_object('key', v_key, 'currency', CASE WHEN v_by_crystal THEN 'crystals' ELSE 'gold' END));
  RETURN jsonb_build_object('success', true, 'key', v_key, 'qty', v_qty, 'item_name', v_item.name,
    'new_gold', CASE WHEN v_by_crystal THEN v_gold ELSE v_gold - v_item.cost END,
    'new_crystals', CASE WHEN v_by_crystal THEN v_crystals - v_item.cost ELSE v_crystals END,
    'new_wood', v_wood - v_wood_cost,
    'new_food', v_food - v_food_cost);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_decor(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_decor(UUID) TO authenticated;

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT v.name, v.descr, 100, 'home_decor', v.meta, v.sort, true
FROM (VALUES
  ('Fish Barrel', 'A barrel brimming with the day''s catch. Fits in any home.', '{"key":"fish_barrel","zone":null,"food_cost":25}'::jsonb, 16),
  ('Sitting Barrel', 'A sturdy Durotar barrel resting on its side. Fits in any home.', '{"key":"sitting_barrel","zone":null,"wood_cost":5}'::jsonb, 17),
  ('Standing Barrel', 'An open-topped folk barrel, handy for storing supplies. Fits in any home.', '{"key":"standing_barrel","zone":null,"wood_cost":5}'::jsonb, 18)
) AS v(name, descr, meta, sort)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items s WHERE s.category = 'home_decor' AND s.metadata->>'key' = v.meta->>'key');
