-- Migration: Filled Treasure Chest (350g + 5 wood) and Gold Treasure pile (200g) decor
-- Purpose: two pieces from the Coffers, for any home.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' IN ('filled_chest', 'gold_pile');

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT v.name, v.descr, v.cost, 'home_decor', v.meta, v.sort, true
FROM (VALUES
  ('Filled Treasure Chest', 'A gilded chest stuffed with gold and jewels. Fits in any home.', 350, '{"key":"filled_chest","zone":null,"wood_cost":5}'::jsonb, 19),
  ('Gold Treasure', 'A glittering dragon''s hoard of coins and trinkets, spilled across the floor. Fits in any home.', 200, '{"key":"gold_pile","zone":null}'::jsonb, 20)
) AS v(name, descr, cost, meta, sort)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items s WHERE s.category = 'home_decor' AND s.metadata->>'key' = v.meta->>'key');
