-- Migration: Hogger - earned decor for 150 Hogger (rare spawn) wins
-- Purpose: the terror of Elwynn, tamed, roaming any home; granted by the game-wins trigger (20261011004300).
--          The Hogger mini-game is game_type 'rarespawn'.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'hogger_npc';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Hogger', 'The terror of Elwynn, finally housebroken. Mostly. Earned by defeating Hogger 150 times.',
       0, 'home_decor', '{"key":"hogger_npc","zone":null,"reward":"rarespawn_wins","reward_game":"rarespawn","reward_goal":150,"reward_text":"Defeat Hogger 150 times"}'::jsonb, 205, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'hogger_npc');

INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, 'hogger_npc', 1 FROM public.profiles p WHERE public.game_wins(p.id, 'rarespawn') >= 150
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
