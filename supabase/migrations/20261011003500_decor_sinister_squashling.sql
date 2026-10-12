-- Migration: Sinister Squashling (rare NPC decor, crystals)
-- Purpose: roaming pumpkin NPC for any home zone, bought with crystals.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'sinister_squashling';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Sinister Squashling', 'Rare! A mischievous little pumpkin that hops around your home casting spooky spells. Fits in any home.',
       6, 'home_decor', '{"key":"sinister_squashling","zone":null,"currency":"crystals","rare":true}'::jsonb, 101, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'sinister_squashling');
