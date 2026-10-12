-- Migration: Ogre Jack-o'-Lantern decor (gold)
-- Purpose: an ogre-faced carved pumpkin with a candle flame, for any home zone.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'ogre_lantern';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Jack-o''-Lantern (Ogre)', 'A big pumpkin carved with a grumpy ogre face, candlelight flickering inside. Fits in any home.',
       150, 'home_decor', '{"key":"ogre_lantern","zone":null}'::jsonb, 10, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'ogre_lantern');
