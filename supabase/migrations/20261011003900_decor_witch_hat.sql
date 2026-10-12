-- Migration: Witch Hat decor (gold)
-- Purpose: a pointed witch's hat to leave lying around any home.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'witch_hat';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Witch Hat', 'A crooked, pointy witch''s hat. Its owner must be around here somewhere... Fits in any home.',
       100, 'home_decor', '{"key":"witch_hat","zone":null}'::jsonb, 11, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'witch_hat');
