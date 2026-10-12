-- Migration: Jack-o'-Lantern decor (gold)
-- Purpose: flaming pumpkin head for any home zone.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'jack_o_lantern';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Jack-o''-Lantern', 'A grinning pumpkin with a flame dancing on top. Hallow''s End all year round. Fits in any home.',
       150, 'home_decor', '{"key":"jack_o_lantern","zone":null}'::jsonb, 9, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'jack_o_lantern');
