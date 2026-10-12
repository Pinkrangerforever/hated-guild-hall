-- Migration: Log Pile decor (25 wood, no gold)
-- Purpose: the lumber-mill log pile (also the wood store in each player's Coffers) for any home.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'log_pile';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Log Pile', 'A big stack of fresh-cut logs from the lumber mill. Fits in any home.',
       0, 'home_decor', '{"key":"log_pile","zone":null,"wood_cost":25}'::jsonb, 14, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'log_pile');
