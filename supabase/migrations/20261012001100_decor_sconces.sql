-- Migration: Dalaran sconce decor (150g each)
-- Purpose: two Dalaran indoor sconces (also lighting the Coffers) for any home.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_decor' AND metadata->>'key' IN ('sconce_a', 'sconce_b');

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT v.name, v.descr, 150, 'home_decor', v.meta, v.sort, true
FROM (VALUES
  ('Dalaran Sconce', 'An elegant Dalaran sconce with a warm, glowing shade. Fits in any home.', '{"key":"sconce_a","zone":null}'::jsonb, 21),
  ('Dalaran Lantern Sconce', 'A slender Dalaran lantern sconce that casts a soft amber glow. Fits in any home.', '{"key":"sconce_b","zone":null}'::jsonb, 22)
) AS v(name, descr, meta, sort)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items s WHERE s.category = 'home_decor' AND s.metadata->>'key' = v.meta->>'key');
