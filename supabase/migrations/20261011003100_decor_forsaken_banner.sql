-- Migration: Forsaken Banner decor
-- Purpose: new Decor Shop piece usable in any home zone (model: models/housing/decor-forsaken-banner.gltf).
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'forsaken_banner';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Forsaken Banner', 'The tattered banner of the Forsaken, raised by those who refused to stay dead. Fits in any home.',
       200, 'home_decor', '{"key":"forsaken_banner","zone":null}'::jsonb, 6, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'forsaken_banner');
