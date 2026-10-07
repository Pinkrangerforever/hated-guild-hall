-- Migration: Add Alpha/Founder perks
-- Purpose: Create exclusive customizations for early players

-- Add active_nameplate_icon column to profiles
ALTER TABLE public.profiles
ADD COLUMN active_nameplate_icon uuid DEFAULT NULL REFERENCES public.shop_items(id);

COMMENT ON COLUMN public.profiles.active_nameplate_icon IS 'User''s selected nameplate icon (shop_items.id). NULL means no active icon.';

-- Insert Alpha Founder Border (tier 5 - special)
INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES (
  'Alpha Founder Border',
  'Exclusive pulsing gold border for early supporters',
  0,
  'roster_name_border',
  '{"tier": 5, "type": "alpha"}',
  1,
  false
) ON CONFLICT DO NOTHING;

-- Insert Alpha Founder Icon
INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES (
  'Alpha Founder Icon',
  'Exclusive Alpha icon badge for nameplate',
  0,
  'nameplate_icon',
  '{"icon_url": "https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/AlphaIcon.png"}',
  1,
  false
) ON CONFLICT DO NOTHING;

-- Give both items to user "Pink" as owned
DO $$
DECLARE
  pink_user_id uuid;
  border_item_id uuid;
  icon_item_id uuid;
BEGIN
  -- Get Pink's user ID
  SELECT id INTO pink_user_id FROM auth.users
  WHERE email = 'pink@example.com' OR (raw_user_meta_data->>'username') = 'Pink';

  IF pink_user_id IS NOT NULL THEN
    -- Get the item IDs we just created
    SELECT id INTO border_item_id FROM public.shop_items
    WHERE name = 'Alpha Founder Border' LIMIT 1;

    SELECT id INTO icon_item_id FROM public.shop_items
    WHERE name = 'Alpha Founder Icon' LIMIT 1;

    -- Insert fulfilled purchases for both items
    INSERT INTO public.shop_purchases (user_id, item_id, fulfilled)
    VALUES
      (pink_user_id, border_item_id, true),
      (pink_user_id, icon_item_id, true)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
