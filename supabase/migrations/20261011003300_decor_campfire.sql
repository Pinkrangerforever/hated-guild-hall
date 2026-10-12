-- Migration: Campfire decor
-- Purpose: new Decor Shop piece usable in any home zone (model: models/housing/decor-campfire.gltf,
--          with a flickering flame and firelight added by the site).
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'campfire';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Campfire', 'A crackling campfire ringed with stones. Warms the paws of any pet. Fits in any home.',
       250, 'home_decor', '{"key":"campfire","zone":null}'::jsonb, 8, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'campfire');
