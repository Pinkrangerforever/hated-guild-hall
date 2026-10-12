-- Migration: Horde Banner decor
-- Purpose: new Decor Shop piece usable in any home zone (model: models/housing/decor-horde-banner.gltf).
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'horde_banner';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Horde Banner', 'A tall clan banner of the Horde, snapping in the wind. Fits in any home. For the Horde!',
       200, 'home_decor', '{"key":"horde_banner","zone":null}'::jsonb, 5, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'horde_banner');
