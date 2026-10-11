-- Migration: Home decor + layouts (Phase 4c)
-- Purpose:
--   1) shop_items category 'home_decor': metadata {key, zone} - zone NULL means usable in any home zone.
--      Starter pieces: Tauren Lamppost (Mulgore), Elwynn Lamp Post + Elwynn Oak (Elwynn), Copper Vein (any).
--   2) player_decor: how many of each decor piece a player owns (shared across all their homes).
--   3) player_homes.layout: where the owner put their houses and decor
--      {"houses": {"1": {"x":..,"z":..,"r":..}}, "decor": [{"k": key, "x":..,"z":..,"r":..}]}
--   4) purchase_decor(item) - buy one piece with gold.
--      save_home_layout(home, layout) - owner only; houses must be built, decor must be owned (counting
--      pieces placed in the owner's other homes), zone-locked pieces only in their zone, on the stage,
--      at most 40 pieces. The stored layout is rebuilt from the validated numbers.
--   5) purchase_shop_item refuses home_decor (it has its own function).
-- Date: 2026-10-11
-- Reverse: DROP FUNCTION purchase_decor(uuid), save_home_layout(uuid, jsonb); DROP TABLE player_decor;
--          ALTER TABLE player_homes DROP COLUMN layout; DELETE FROM shop_items WHERE category = 'home_decor';

ALTER TABLE public.purchase_log DROP CONSTRAINT IF EXISTS valid_type;
ALTER TABLE public.purchase_log ADD CONSTRAINT valid_type CHECK (purchase_type = ANY (ARRAY[
  'shop_item', 'dealer_access', 'food_bundle', 'wood_bundle', 'nameplate_effect', 'roster_border',
  'sticker', 'backdrop', 'house_addition', 'house_tier', 'home_decor']));

-- 1) starter pieces
INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT v.name, v.descr, v.cost, 'home_decor', v.meta, v.sort, true
FROM (VALUES
  ('Tauren Lamppost', 'A carved Thunder Bluff lamppost to light the plains.', 150, '{"key":"mulgore_lamppost","zone":"mulgore_bluffs"}'::jsonb, 1),
  ('Elwynn Lamp Post', 'A Stormwind-style lantern post, flickering at dusk.', 150, '{"key":"elwynn_lamppost","zone":"elwynn_cabin"}'::jsonb, 2),
  ('Elwynn Oak', 'A tall Elwynn oak that sways in the breeze.', 200, '{"key":"elwynn_oak","zone":"elwynn_cabin"}'::jsonb, 3),
  ('Copper Vein', 'A glittering copper node. Fits in any home.', 250, '{"key":"copper_vein","zone":null}'::jsonb, 4)
) AS v(name, descr, cost, meta, sort)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items s WHERE s.category = 'home_decor' AND s.metadata->>'key' = v.meta->>'key');

-- 2) inventory
CREATE TABLE IF NOT EXISTS public.player_decor (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_key TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 0 CHECK (qty >= 0),
  PRIMARY KEY (user_id, item_key)
);
ALTER TABLE public.player_decor ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players see their own decor" ON public.player_decor;
CREATE POLICY "Players see their own decor" ON public.player_decor FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.player_decor FROM anon, authenticated;
GRANT SELECT ON public.player_decor TO authenticated;

-- 3) layouts
ALTER TABLE public.player_homes ADD COLUMN IF NOT EXISTS layout JSONB;

-- 4) functions
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
  SELECT pr.gold INTO v_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_gold IS NULL OR v_gold < v_item.cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;
  UPDATE public.profiles pr
  SET gold = pr.gold - v_item.cost, gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
  WHERE pr.id = v_user_id;
  INSERT INTO public.player_decor (user_id, item_key, qty) VALUES (v_user_id, v_key, 1)
  ON CONFLICT (user_id, item_key) DO UPDATE SET qty = public.player_decor.qty + 1
  RETURNING qty INTO v_qty;
  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'home_decor', v_item.cost, v_item.name, jsonb_build_object('key', v_key));
  RETURN jsonb_build_object('success', true, 'key', v_key, 'qty', v_qty, 'new_gold', v_gold - v_item.cost, 'item_name', v_item.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_home_layout(p_home_id UUID, p_layout JSONB)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_home RECORD;
  v_houses JSONB := '{}'::jsonb;
  v_decor JSONB := '[]'::jsonb;
  v_key TEXT;
  v_val JSONB;
  v_x NUMERIC; v_z NUMERIC; v_r NUMERIC;
  v_zone TEXT;
  v_found BOOLEAN;
  v_used INTEGER;
  v_owned INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  SELECT h.id, h.zone, h.house_tier INTO v_home
  FROM public.player_homes h WHERE h.id = p_home_id AND h.user_id = v_user_id FOR UPDATE;
  IF v_home.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Home not found');
  END IF;
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Bad layout');
  END IF;

  -- houses: only tiers that are built, each once (object keys), on the stage
  IF jsonb_typeof(p_layout->'houses') = 'object' THEN
    FOR v_key, v_val IN SELECT * FROM jsonb_each(p_layout->'houses') LOOP
      IF v_key NOT IN ('1', '2', '3') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unknown house');
      END IF;
      IF v_key::INT > v_home.house_tier THEN
        RETURN jsonb_build_object('success', false, 'error', 'That house is not built yet');
      END IF;
      BEGIN
        v_x := round((v_val->>'x')::NUMERIC, 2); v_z := round((v_val->>'z')::NUMERIC, 2); v_r := round((v_val->>'r')::NUMERIC, 3);
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bad position');
      END;
      IF v_x IS NULL OR v_z IS NULL OR v_r IS NULL OR abs(v_x) > 6.5 OR abs(v_z) > 3.5 OR abs(v_r) > 7 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A house is off the stage');
      END IF;
      v_houses := v_houses || jsonb_build_object(v_key, jsonb_build_object('x', v_x, 'z', v_z, 'r', v_r));
    END LOOP;
  END IF;

  -- decor: known, allowed in this zone, on the stage, at most 40
  IF jsonb_typeof(p_layout->'decor') = 'array' THEN
    IF jsonb_array_length(p_layout->'decor') > 40 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Too many pieces (max 40)');
    END IF;
    FOR v_val IN SELECT * FROM jsonb_array_elements(p_layout->'decor') LOOP
      v_key := v_val->>'k';
      v_found := NULL;
      SELECT true, si.metadata->>'zone' INTO v_found, v_zone
      FROM public.shop_items si WHERE si.category = 'home_decor' AND si.metadata->>'key' = v_key LIMIT 1;
      IF v_found IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unknown piece');
      END IF;
      IF v_zone IS NOT NULL AND v_zone <> v_home.zone THEN
        RETURN jsonb_build_object('success', false, 'error', 'That piece belongs to another home');
      END IF;
      BEGIN
        v_x := round((v_val->>'x')::NUMERIC, 2); v_z := round((v_val->>'z')::NUMERIC, 2); v_r := round((v_val->>'r')::NUMERIC, 3);
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bad position');
      END;
      IF v_x IS NULL OR v_z IS NULL OR v_r IS NULL OR abs(v_x) > 6.5 OR abs(v_z) > 3.5 OR abs(v_r) > 7 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A piece is off the stage');
      END IF;
      v_decor := v_decor || jsonb_build_array(jsonb_build_object('k', v_key, 'x', v_x, 'z', v_z, 'r', v_r));
    END LOOP;
  END IF;

  -- ownership: pieces here + pieces already placed in the owner's other homes
  FOR v_key, v_used IN
    SELECT s.d->>'k', count(*)::INT FROM (
      SELECT jsonb_array_elements(v_decor) AS d
      UNION ALL
      SELECT jsonb_array_elements(COALESCE(h.layout->'decor', '[]'::jsonb))
      FROM public.player_homes h WHERE h.user_id = v_user_id AND h.id <> v_home.id
    ) s GROUP BY 1
  LOOP
    SELECT COALESCE((SELECT pd.qty FROM public.player_decor pd WHERE pd.user_id = v_user_id AND pd.item_key = v_key), 0) INTO v_owned;
    IF v_used > v_owned THEN
      RETURN jsonb_build_object('success', false, 'error', 'You placed more pieces than you own');
    END IF;
  END LOOP;

  UPDATE public.player_homes h SET layout = jsonb_build_object('houses', v_houses, 'decor', v_decor) WHERE h.id = v_home.id;
  RETURN jsonb_build_object('success', true, 'layout', jsonb_build_object('houses', v_houses, 'decor', v_decor));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_decor(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.save_home_layout(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_decor(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_home_layout(UUID, JSONB) TO authenticated;

-- 5) purchase_shop_item: also refuse decor
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_item_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_item RECORD;
  v_gold INTEGER;
  v_new_gold INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_item FROM shop_items WHERE id = p_item_id;
  IF v_item IS NULL THEN
    RETURN json_build_object('success', false, 'reason', 'item_not_found');
  END IF;

  IF NOT v_item.active THEN
    RETURN json_build_object('success', false, 'reason', 'item_unavailable');
  END IF;

  -- Pets, Auction House bundles and homes have their own purchase functions
  IF v_item.category IN ('pet_egg', 'resource_bundle', 'home_location', 'home_decor') THEN
    RETURN json_build_object('success', false, 'reason', 'item_unavailable');
  END IF;

  SELECT gold INTO v_gold FROM profiles WHERE id = v_user_id;
  IF v_gold IS NULL OR v_gold < v_item.cost THEN
    RETURN json_build_object('success', false, 'reason', 'insufficient_gold');
  END IF;

  v_new_gold := v_gold - v_item.cost;

  PERFORM set_config('app.allow_purchase', 'true', true);

  UPDATE profiles SET gold = v_new_gold WHERE id = v_user_id;

  INSERT INTO public.gold_transactions (user_id, transaction_type, amount, reason, source)
  VALUES (v_user_id, 'spent', v_item.cost, 'Shop purchase: ' || v_item.name, 'shop');

  INSERT INTO shop_purchases (user_id, item_id, item_name, cost_paid, fulfilled)
  VALUES (v_user_id, p_item_id, v_item.name, v_item.cost, true);

  RETURN json_build_object('success', true, 'new_gold', v_new_gold, 'item_name', v_item.name);
END;
$$;


