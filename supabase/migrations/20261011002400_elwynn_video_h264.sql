-- Migration: Cabin in Elwynn video in a browser-playable format
-- Purpose: the original upload is MPEG-4 Part 2 (mp4v), which browsers can't play. Point the shop item
--          at the H.264 1080p/30fps re-encode (Housing/Elwynn Cabin/Elwynn Cabin.mp4).
-- Date: 2026-10-11
-- Reverse: set metadata.video back to .../Cabin%20In%20the%20Woods%20of%20Elwynn3(best).mp4

UPDATE public.shop_items
SET metadata = jsonb_set(metadata, '{video}', to_jsonb('https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Elwynn%20Cabin/Elwynn%20Cabin.mp4'::text))
WHERE category = 'home_location' AND metadata->>'zone' = 'elwynn_cabin';
