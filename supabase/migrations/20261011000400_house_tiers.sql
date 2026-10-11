-- Migration: Phase 4b - Build / upgrade the house on a home location with wood
-- Purpose: upgrade_house(p_home_id) raises player_homes.house_tier by one and charges wood:
--          Tier 1 = 100 wood, Tier 2 = 500 wood, Tier 3 = 1000 wood. Owner only; max tier 3.
--          (A new function name: the old disabled upgrade_house(uuid, integer) is left alone.)
-- Date: 2026-10-11
-- Reverse: DROP FUNCTION public.build_house_tier(uuid); restore purchase_log valid_type without 'house_tier'

ALTER TABLE public.purchase_log DROP CONSTRAINT IF EXISTS valid_type;
ALTER TABLE public.purchase_log ADD CONSTRAINT valid_type CHECK (purchase_type = ANY (ARRAY[
  'shop_item', 'dealer_access', 'food_bundle', 'wood_bundle', 'nameplate_effect', 'roster_border',
  'sticker', 'backdrop', 'house_addition', 'house_tier']));

CREATE OR REPLACE FUNCTION public.build_house_tier(p_home_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_home RECORD;
  v_wood INTEGER;
  v_next INTEGER;
  v_cost INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;

  -- Lock the profile first so two clicks can't both spend the same wood
  SELECT pr.wood INTO v_wood FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;

  SELECT h.id, h.zone, h.house_tier INTO v_home
  FROM public.player_homes h WHERE h.id = p_home_id AND h.user_id = v_user_id FOR UPDATE;
  IF v_home.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Home not found');
  END IF;
  IF v_home.house_tier >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Your house is already fully upgraded');
  END IF;

  v_next := v_home.house_tier + 1;
  v_cost := CASE v_next WHEN 1 THEN 100 WHEN 2 THEN 500 ELSE 1000 END;
  IF COALESCE(v_wood, 0) < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', format('You need %s wood', v_cost), 'cost', v_cost);
  END IF;

  UPDATE public.profiles pr
  SET wood = COALESCE(pr.wood, 0) - v_cost,
      wood_spent_total = COALESCE(pr.wood_spent_total, 0) + v_cost
  WHERE pr.id = v_user_id;

  UPDATE public.player_homes h SET house_tier = v_next WHERE h.id = v_home.id;

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, NULL, 'house_tier', v_cost, format('House tier %s (%s)', v_next, v_home.zone),
          jsonb_build_object('home_id', v_home.id, 'zone', v_home.zone, 'tier', v_next, 'resource', 'wood'));

  RETURN jsonb_build_object('success', true, 'tier', v_next, 'cost', v_cost, 'wood', COALESCE(v_wood, 0) - v_cost);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.build_house_tier(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.build_house_tier(UUID) TO authenticated;
