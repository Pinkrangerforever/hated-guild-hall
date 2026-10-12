-- Migration: rare decor bought with crystals + the Headless Horseman
-- Purpose: decor items with metadata.currency = 'crystals' cost crystals (shop_items.cost = crystal count)
--          instead of gold. First one: the Headless Horseman, a roaming NPC for any home zone.
-- Date: 2026-10-11
-- Reverse: re-run purchase_decor from 20261011002500;
--          DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'headless_horseman';

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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  SELECT si.id, si.name, si.cost, si.metadata INTO v_item
  FROM public.shop_items si WHERE si.id = p_item_id AND si.category = 'home_decor' AND si.active = true;
  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That piece is not for sale');
  END IF;
  v_key := v_item.metadata->>'key';
  v_by_crystal := COALESCE(v_item.metadata->>'currency', 'gold') = 'crystals';
  SELECT pr.gold, COALESCE(pr.crystals, 0) INTO v_gold, v_crystals FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
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
  INSERT INTO public.player_decor (user_id, item_key, qty) VALUES (v_user_id, v_key, 1)
  ON CONFLICT (user_id, item_key) DO UPDATE SET qty = public.player_decor.qty + 1
  RETURNING qty INTO v_qty;
  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'home_decor', v_item.cost, v_item.name, jsonb_build_object('key', v_key, 'currency', CASE WHEN v_by_crystal THEN 'crystals' ELSE 'gold' END));
  RETURN jsonb_build_object('success', true, 'key', v_key, 'qty', v_qty, 'item_name', v_item.name,
    'new_gold', CASE WHEN v_by_crystal THEN v_gold ELSE v_gold - v_item.cost END,
    'new_crystals', CASE WHEN v_by_crystal THEN v_crystals - v_item.cost ELSE v_crystals END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_decor(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_decor(UUID) TO authenticated;

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'The Headless Horseman', 'Rare! The Horseman rides your grounds and cackles into the night. Fits in any home.',
       10, 'home_decor', '{"key":"headless_horseman","zone":null,"currency":"crystals","rare":true}'::jsonb, 100, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'headless_horseman');
