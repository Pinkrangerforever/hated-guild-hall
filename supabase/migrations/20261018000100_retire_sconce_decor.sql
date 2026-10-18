-- Migration: retire the Dalaran sconce decor from the Decor Shop
-- Purpose: the two sconces don't sit well in the home scenes, so they're no longer sold. Their rows stay (inactive)
--          so anyone who bought one keeps it in their inventory; the models still light the Guild Coffers.
-- Date: 2026-10-18
-- Reverse: UPDATE public.shop_items SET active = true WHERE category = 'home_decor' AND metadata->>'key' IN ('sconce_a', 'sconce_b');

UPDATE public.shop_items SET active = false
 WHERE category = 'home_decor' AND metadata->>'key' IN ('sconce_a', 'sconce_b');
