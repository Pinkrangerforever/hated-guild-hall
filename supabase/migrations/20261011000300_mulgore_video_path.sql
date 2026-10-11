-- Migration: Mulgore Bluffs video moved into its own R2 folder
-- Date: 2026-10-11
-- Reverse: set metadata.video back to .../Housing/Mulgore%20Bluffs.mp4
UPDATE public.shop_items
SET metadata = jsonb_set(metadata, '{video}', to_jsonb('https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/Housing/Mulgore%20Bluffs/Mulgore%20Bluffs.mp4'::text))
WHERE category = 'home_location' AND metadata->>'zone' = 'mulgore_bluffs';
