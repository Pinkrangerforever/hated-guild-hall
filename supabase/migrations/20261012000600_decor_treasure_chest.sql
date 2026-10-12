-- Migration: Treasure Chest decor (200g + 5 wood)
-- Purpose: the WoW treasure chest (also the one in each player's Coffers) as a Decor Shop piece for any home.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'treasure_chest';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Treasure Chest', 'An iron-bound treasure chest, lid thrown open. Fits in any home.',
       200, 'home_decor', '{"key":"treasure_chest","zone":null,"wood_cost":5}'::jsonb, 13, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'treasure_chest');
