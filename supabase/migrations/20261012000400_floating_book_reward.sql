-- Migration: Floating Book - earned decor for 150 correct Trivia answers
-- Purpose: an enchanted tome hovering in a soft arcane glow; granted by the game-wins trigger (20261011004300).
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'floating_book';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Floating Book', 'An enchanted tome of the Bronze Dragonflight, hovering open in a soft arcane glow. Earned by answering 150 Trivia questions correctly.',
       0, 'home_decor', '{"key":"floating_book","zone":null,"reward":"trivia_wins","reward_game":"trivia","reward_goal":150,"reward_text":"Answer 150 Trivia questions correctly"}'::jsonb, 207, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'floating_book');

INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, 'floating_book', 1 FROM public.profiles p WHERE public.game_wins(p.id, 'trivia') >= 150
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
