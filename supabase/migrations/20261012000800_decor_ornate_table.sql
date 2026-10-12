-- Migration: Ornate Round Table decor (200g + 5 wood)
-- Purpose: the Blood Elf round table (also the crystal table in each player's Coffers) for any home.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'ornate_table';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Ornate Round Table', 'A gilded round table of elven make, perfect for showing off your finest crystals. Fits in any home.',
       200, 'home_decor', '{"key":"ornate_table","zone":null,"wood_cost":5}'::jsonb, 15, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'ornate_table');
