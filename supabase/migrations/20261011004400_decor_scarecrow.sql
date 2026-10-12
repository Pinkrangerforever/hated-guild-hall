-- Migration: Scarecrow decor (Hallow's End holiday, gold)
-- Purpose: Westfall scarecrow for any home, shown in the Decor Shop's limited-time holiday section.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'scarecrow';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Scarecrow', 'A ragged Westfall scarecrow to keep the crows (and the neighbors) away. Fits in any home.',
       150, 'home_decor', '{"key":"scarecrow","zone":null,"holiday":"hallows_end"}'::jsonb, 12, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'scarecrow');
