-- Migration: rare NPC prices
-- Purpose: Headless Horseman 20 crystals, Sinister Squashling 10 crystals.
-- Date: 2026-10-11
-- Reverse: set cost back to 10 / 6.

UPDATE public.shop_items SET cost = 20 WHERE category = 'home_decor' AND metadata->>'key' = 'headless_horseman';
UPDATE public.shop_items SET cost = 10 WHERE category = 'home_decor' AND metadata->>'key' = 'sinister_squashling';
