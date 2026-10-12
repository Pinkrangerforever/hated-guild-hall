-- Migration: Troll Banner decor
-- Purpose: new Decor Shop piece usable in any home zone (model: models/housing/decor-troll-banner.gltf).
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'troll_banner';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Troll Banner', 'A Darkspear tournament banner. Stay away from da voodoo, mon. Fits in any home.',
       200, 'home_decor', '{"key":"troll_banner","zone":null}'::jsonb, 7, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'troll_banner');
