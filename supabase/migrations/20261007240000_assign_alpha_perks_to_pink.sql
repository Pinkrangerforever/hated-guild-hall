-- Migration: Assign Alpha Founder perks to Pink
-- Purpose: Give Pink user both Alpha items as owned

DO $$
DECLARE
  pink_id uuid;
  border_id uuid;
  icon_id uuid;
BEGIN
  -- Get Pink's user ID from profiles table by character name
  SELECT id INTO pink_id FROM public.profiles
  WHERE LOWER(character_name) = 'pink'
  LIMIT 1;

  IF pink_id IS NOT NULL THEN
    -- Get the Alpha Founder Border item ID
    SELECT id INTO border_id FROM public.shop_items
    WHERE name = 'Alpha Founder Border'
    LIMIT 1;

    -- Get the Alpha Founder Icon item ID
    SELECT id INTO icon_id FROM public.shop_items
    WHERE name = 'Alpha Founder Icon'
    LIMIT 1;

    -- Insert purchases to give Pink ownership of both items
    -- Delete any existing records first to avoid conflicts
    IF border_id IS NOT NULL THEN
      DELETE FROM public.shop_purchases WHERE user_id = pink_id AND item_id = border_id;
      INSERT INTO public.shop_purchases (user_id, item_id, fulfilled)
      VALUES (pink_id, border_id, true);
    END IF;

    IF icon_id IS NOT NULL THEN
      DELETE FROM public.shop_purchases WHERE user_id = pink_id AND item_id = icon_id;
      INSERT INTO public.shop_purchases (user_id, item_id, fulfilled)
      VALUES (pink_id, icon_id, true);
    END IF;

    RAISE NOTICE 'Alpha perks assigned to Pink (ID: %)', pink_id;
  ELSE
    RAISE WARNING 'Could not find user Pink in profiles table';
  END IF;
END $$;
