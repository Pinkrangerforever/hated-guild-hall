-- Migration: decor prices (some cost wood too) + achievement decor needs 200 wins
-- Purpose:
--   * purchase_decor: metadata.wood_cost is charged in addition to the gold / crystal price.
--   * Scarecrow 200g + 10 wood; Horde / Forsaken / Troll banners 150g + 5 wood; Copper Vein 150g; Campfire 150g.
--   * Mini-game achievement decor goal 150 -> 200 wins (players already granted keep theirs).
-- Date: 2026-10-12
-- Reverse: re-run purchase_decor from 20261011004200; restore costs (scarecrow 150, banners 200, copper 250,
--          campfire 250), drop wood_cost; set reward_goal back to 150.

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
  SELECT pr.gold, COALESCE(pr.crystals, 0), COALESCE(pr.wood, 0) INTO v_gold, v_crystals, v_wood FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
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
    'new_wood', v_wood - v_wood_cost);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_decor(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_decor(UUID) TO authenticated;

UPDATE public.shop_items SET cost = 200, metadata = metadata || '{"wood_cost":10}'::jsonb
WHERE category = 'home_decor' AND metadata->>'key' = 'scarecrow';
UPDATE public.shop_items SET cost = 150, metadata = metadata || '{"wood_cost":5}'::jsonb
WHERE category = 'home_decor' AND metadata->>'key' IN ('horde_banner', 'forsaken_banner', 'troll_banner');
UPDATE public.shop_items SET cost = 150 WHERE category = 'home_decor' AND metadata->>'key' IN ('copper_vein', 'campfire');

UPDATE public.shop_items
SET metadata = metadata || '{"reward_goal":200}'::jsonb
              || jsonb_build_object('reward_text', replace(metadata->>'reward_text', '150', '200')),
    description = replace(description, '150', '200')
WHERE category = 'home_decor' AND metadata ? 'reward_game';
