-- Migration: Hallow's End holiday decor
-- Purpose: tag the Halloween pieces so the Decor Shop shows them in its "Limited Time Holiday" section.
-- Date: 2026-10-11
-- Reverse: UPDATE shop_items SET metadata = metadata - 'holiday' WHERE metadata->>'holiday' = 'hallows_end';

UPDATE public.shop_items SET metadata = metadata || '{"holiday":"hallows_end"}'::jsonb
WHERE category = 'home_decor'
  AND metadata->>'key' IN ('headless_horseman', 'sinister_squashling', 'flying_broom', 'jack_o_lantern', 'ogre_lantern', 'witch_hat');
