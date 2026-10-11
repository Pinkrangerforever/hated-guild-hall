-- Migration: Cabin in Elwynn home location
-- Purpose: second home location for sale in the shop (zone elwynn_cabin, same price as Mulgore Bluffs).
--          The scene (video backdrop, ground, lamp post, tree) is configured in HOME_ZONES in index.html.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'elwynn_cabin';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Cabin in Elwynn',
       'A quiet cabin among the tall oaks of Elwynn Forest, a lantern lit by the path. Claim it to call home.',
       1500, 'home_location',
       jsonb_build_object('zone', 'elwynn_cabin',
                          'video', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Elwynn%20Cabin/Cabin%20In%20the%20Woods%20of%20Elwynn3(best).mp4'),
       2, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'elwynn_cabin');
