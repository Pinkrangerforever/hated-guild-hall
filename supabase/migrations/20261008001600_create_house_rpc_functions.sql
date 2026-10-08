-- Migration: Create RPC functions for house building system
-- Purpose: Server-side validation for house upgrades and addition toggling
-- Date: 2026-10-07
-- Fixed: Use DECLARE variables to eliminate ambiguous column references

-- ============================================================================
-- HOUSE MANAGEMENT FUNCTIONS
-- ============================================================================

-- Initialize house for user (called on first purchase)
CREATE OR REPLACE FUNCTION initialize_house(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
BEGIN
  -- Check if house already exists
  IF EXISTS(SELECT 1 FROM public.house WHERE user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'House already exists');
  END IF;

  -- Create house with default values
  INSERT INTO public.house (user_id, house_tier)
  VALUES (v_user_id, 1);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'House created',
    'house_tier', 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Upgrade house: Validate wood, upgrade tier
CREATE OR REPLACE FUNCTION upgrade_house(
  user_id UUID,
  target_tier INTEGER
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_house RECORD;
  user_wood INTEGER;
  upgrade_cost INTEGER;
BEGIN
  -- Get user's house
  SELECT house_tier INTO user_house FROM public.house WHERE user_id = v_user_id;

  IF user_house IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'House not found');
  END IF;

  -- Validate target tier
  IF target_tier < 1 OR target_tier > 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid tier (1-3)');
  END IF;

  -- Validate upgrade path (can only upgrade by 1 tier)
  IF target_tier != user_house.house_tier + 1 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Can only upgrade one tier at a time',
      'current_tier', user_house.house_tier
    );
  END IF;

  -- Determine cost based on tier
  upgrade_cost := CASE
    WHEN target_tier = 2 THEN 500
    WHEN target_tier = 3 THEN 1000
    ELSE 0
  END;

  -- Get user's wood balance
  SELECT wood INTO user_wood FROM public.profiles WHERE id = v_user_id;

  IF user_wood IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate wood balance
  IF user_wood < upgrade_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient wood',
      'current_wood', user_wood,
      'cost', upgrade_cost
    );
  END IF;

  -- Deduct wood
  UPDATE public.profiles
  SET wood = wood - upgrade_cost, wood_spent_total = wood_spent_total + upgrade_cost, updated_at = now()
  WHERE id = v_user_id;

  -- Upgrade house
  UPDATE public.house
  SET house_tier = target_tier, updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_tier', target_tier,
    'new_wood', user_wood - upgrade_cost,
    'cost', upgrade_cost,
    'message', format('House upgraded to Tier %s', target_tier)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Select active backdrop
CREATE OR REPLACE FUNCTION select_backdrop(
  user_id UUID,
  backdrop_item_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_backdrop_item_id UUID := backdrop_item_id;
  owns_backdrop BOOLEAN;
BEGIN
  -- Validate user owns this backdrop
  SELECT EXISTS(
    SELECT 1 FROM public.shop_items
    WHERE id = v_backdrop_item_id
    AND category = 'backdrop'
  ) INTO owns_backdrop;

  IF NOT owns_backdrop THEN
    RETURN jsonb_build_object('success', false, 'error', 'Backdrop not found or invalid');
  END IF;

  -- Update active backdrop
  UPDATE public.house
  SET backdrop_id = v_backdrop_item_id, updated_at = now()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'House not found');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'backdrop_id', v_backdrop_item_id,
    'message', 'Backdrop changed'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- HOUSE ADDITIONS FUNCTIONS
-- ============================================================================

-- Add house addition (called after purchase)
CREATE OR REPLACE FUNCTION add_house_addition(
  user_id UUID,
  addition_item_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_addition_item_id UUID := addition_item_id;
  is_valid_addition BOOLEAN;
BEGIN
  -- Validate item exists and is house_addition category
  SELECT EXISTS(
    SELECT 1 FROM public.shop_items
    WHERE id = v_addition_item_id
    AND category = 'house_addition'
  ) INTO is_valid_addition;

  IF NOT is_valid_addition THEN
    RETURN jsonb_build_object('success', false, 'error', 'Addition not found or invalid');
  END IF;

  -- Check if already owned
  IF EXISTS(SELECT 1 FROM public.house_additions WHERE user_id = v_user_id AND addition_item_id = v_addition_item_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already own this addition');
  END IF;

  -- Add addition (defaults to active = true)
  INSERT INTO public.house_additions (user_id, addition_item_id, is_active)
  VALUES (v_user_id, v_addition_item_id, true);

  RETURN jsonb_build_object(
    'success', true,
    'addition_id', v_addition_item_id,
    'is_active', true,
    'message', 'Addition added to house'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Toggle house addition active status
CREATE OR REPLACE FUNCTION toggle_house_addition(
  user_id UUID,
  addition_id UUID
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  v_addition_id UUID := addition_id;
  current_active BOOLEAN;
  new_active BOOLEAN;
BEGIN
  -- Get current active status
  SELECT is_active INTO current_active FROM public.house_additions
  WHERE id = v_addition_id AND user_id = v_user_id;

  IF current_active IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Addition not found');
  END IF;

  -- Toggle
  new_active := NOT current_active;

  -- Update
  UPDATE public.house_additions
  SET is_active = new_active, updated_at = now()
  WHERE id = v_addition_id AND user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'addition_id', v_addition_id,
    'is_active', new_active,
    'message', format('Addition %s', CASE WHEN new_active THEN 'enabled' ELSE 'disabled' END)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Get all user's house data (for profile page)
CREATE OR REPLACE FUNCTION get_house_data(fetch_user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_fetch_user_id UUID := fetch_user_id;
  house_data RECORD;
  additions_json JSONB;
BEGIN
  -- Get house info
  SELECT house_tier, backdrop_id INTO house_data FROM public.house WHERE user_id = v_fetch_user_id;

  -- Get additions
  SELECT jsonb_agg(
    jsonb_build_object(
      'addition_id', id,
      'item_id', addition_item_id,
      'is_active', is_active
    )
  ) INTO additions_json FROM public.house_additions WHERE user_id = v_fetch_user_id;

  -- Return combined data
  RETURN jsonb_build_object(
    'house_tier', COALESCE(house_data.house_tier, 1),
    'backdrop_id', house_data.backdrop_id,
    'additions', COALESCE(additions_json, '[]'::jsonb)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
