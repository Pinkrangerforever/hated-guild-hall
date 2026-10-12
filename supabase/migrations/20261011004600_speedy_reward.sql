-- Migration: Speedy - earned decor for 150 Fishing wins
-- Purpose: a slow, happy turtle that roams any home; granted by the game-wins trigger (20261011004300).
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'speedy';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Speedy', 'Slow and steady wins the race. A cheerful turtle that plods around your home. Earned by clearing the Fishing mini-game 150 times.',
       0, 'home_decor', '{"key":"speedy","zone":null,"reward":"fishing_wins","reward_game":"fishing","reward_goal":150,"reward_text":"Clear the Fishing mini-game 150 times"}'::jsonb, 204, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'speedy');

-- anyone already there
INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, 'speedy', 1 FROM public.profiles p WHERE public.game_wins(p.id, 'fishing') >= 150
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
