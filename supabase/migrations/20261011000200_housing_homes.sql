-- Migration: Phase 4a - Home locations
-- Purpose:
--   1) Turn on the Auction House Wood Bundle (10 wood for 60g, 200/day).
--   2) player_homes: one row per home location a player owns (zone backdrop), with the house tier
--      (0 = no house yet; 1-3 come in Phase 4b) and which home is shown on their profile.
--   3) Shop item "Mulgore Bluffs" (category home_location) + purchase_home_location / set_active_home RPCs.
--   4) purchase_shop_item refuses home_location items (they have their own function).
--   The old house / house_additions tables stay untouched and disabled (see 20261010000800).
-- Date: 2026-10-11
-- Reverse: DROP FUNCTION purchase_home_location(uuid), set_active_home(uuid); DROP TABLE player_homes;
--          DELETE FROM shop_items WHERE category = 'home_location';
--          UPDATE shop_items SET active = false, metadata = metadata || '{"coming_soon":true}' WHERE name = 'Wood Bundle';

-- ============================================================================
-- 1) Wood Bundle on sale
-- ============================================================================
UPDATE public.shop_items
SET active = true, metadata = metadata - 'coming_soon'
WHERE category = 'resource_bundle' AND metadata->>'resource' = 'wood';

-- ============================================================================
-- 2) player_homes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.player_homes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  zone TEXT NOT NULL,
  house_tier INTEGER NOT NULL DEFAULT 0 CHECK (house_tier BETWEEN 0 AND 3),
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, zone)
);
CREATE INDEX IF NOT EXISTS idx_player_homes_user ON public.player_homes(user_id);

ALTER TABLE public.player_homes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone signed in can view homes" ON public.player_homes;
CREATE POLICY "Anyone signed in can view homes" ON public.player_homes FOR SELECT TO authenticated USING (true);
-- No insert/update/delete policies: changes only through the functions below.
REVOKE ALL ON public.player_homes FROM anon, authenticated;
GRANT SELECT ON public.player_homes TO authenticated;

-- ============================================================================
-- 3) Shop item + functions
-- ============================================================================
INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Mulgore Bluffs',
       'Windswept golden plains beneath the bluffs of Thunder Bluff. Claim a plot to call home.',
       1500, 'home_location',
       jsonb_build_object('zone', 'mulgore_bluffs',
                          'video', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Mulgore%20Bluffs.mp4'),
       1, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'mulgore_bluffs');

CREATE OR REPLACE FUNCTION public.purchase_home_location(p_item_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_item RECORD;
  v_zone TEXT;
  v_gold INTEGER;
  v_first BOOLEAN;
  v_home_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;

  SELECT si.id, si.name, si.cost, si.metadata INTO v_item
  FROM public.shop_items si
  WHERE si.id = p_item_id AND si.category = 'home_location' AND si.active = true;
  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That home is not for sale');
  END IF;
  v_zone := v_item.metadata->>'zone';

  SELECT pr.gold INTO v_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.player_homes h WHERE h.user_id = v_user_id AND h.zone = v_zone) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already own this home');
  END IF;
  IF v_gold IS NULL OR v_gold < v_item.cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  UPDATE public.profiles pr
  SET gold = pr.gold - v_item.cost,
      gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
  WHERE pr.id = v_user_id;

  v_first := NOT EXISTS (SELECT 1 FROM public.player_homes h WHERE h.user_id = v_user_id);
  INSERT INTO public.player_homes (user_id, zone, is_active)
  VALUES (v_user_id, v_zone, v_first)
  RETURNING id INTO v_home_id;

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'shop_item', v_item.cost, v_item.name,
          jsonb_build_object('zone', v_zone, 'home_id', v_home_id));

  RETURN jsonb_build_object('success', true, 'home_id', v_home_id, 'zone', v_zone,
                            'new_gold', v_gold - v_item.cost, 'item_name', v_item.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_active_home(p_home_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.player_homes h WHERE h.id = p_home_id AND h.user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Home not found');
  END IF;
  UPDATE public.player_homes h SET is_active = (h.id = p_home_id) WHERE h.user_id = v_user_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_home_location(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_active_home(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_home_location(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_active_home(UUID) TO authenticated;

-- ============================================================================
-- 4) purchase_shop_item: also refuse home locations
-- ============================================================================
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
  IF v_item.category IN ('pet_egg', 'resource_bundle', 'home_location') THEN
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
