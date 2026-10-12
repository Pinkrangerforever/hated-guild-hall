-- Migration: Darkshire Drive home location
-- Purpose: third home location in the shop (zone darkshire_drive, same price as the others).
--          Scene (moonlit Duskwood video, grass/cobblestone stage, sign archway, lamp post) lives in HOME_ZONES.
-- Date: 2026-10-11
-- Reverse: DELETE FROM shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'darkshire_drive';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Darkshire Drive',
       'A lamplit lane on the edge of Darkshire, deep in Duskwood where the night never ends. Brave enough to call it home?',
       1500, 'home_location',
       jsonb_build_object('zone', 'darkshire_drive',
                          'video', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Darkshire%20Drive/Darkshire%20Drive%201080.mp4'),
       3, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_location' AND metadata->>'zone' = 'darkshire_drive');
