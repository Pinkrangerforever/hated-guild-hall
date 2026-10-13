-- Migration: Ashenvale Glade home location
-- Purpose: fourth home location in the shop (zone ashenvale_glade, 1500g like the others). The scene
--          (twilight forest video, moss/road/stone stage, Kaldorei gazebo, priestess fountain) is in HOME_ZONES.
-- Date: 2026-10-12
-- Reverse: DELETE FROM shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'ashenvale_glade';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Ashenvale Glade', 'A moonlit glade deep in the ancient forest of Ashenvale, beneath a Kaldorei gazebo and a priestess fountain.',
       1500, 'home_location',
       jsonb_build_object('zone', 'ashenvale_glade',
                          'video', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Ashenvale%20Glade/Ashenvale%20Glade%201080.mp4'),
       4, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'ashenvale_glade');
