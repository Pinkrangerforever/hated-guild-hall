-- Migration: Flying Broomstick (rare NPC decor, crystals)
-- Purpose: an enchanted broom that takes off, swoops around and lands in any home zone.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'flying_broom';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Flying Broomstick', 'Rare! An enchanted broom that swoops around your home all on its own. Fits in any home.',
       15, 'home_decor', '{"key":"flying_broom","zone":null,"currency":"crystals","rare":true}'::jsonb, 102, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'flying_broom');
