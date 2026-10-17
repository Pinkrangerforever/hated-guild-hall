-- Migration: Phoenix Egg in the shop (fourth pet species)
-- Purpose: purchase_pet_egg matches shop items by metadata.pet_type, so a shop row is all players need to buy one.
--          The egg is the gryphon egg's model in its red/gold skin; it hatches into a phoenix hatchling, grows into
--          a riding phoenix and then an Al'ar-style phoenix (models/phoenix-*.gltf, R2 Phoenix-*/). Same price as
--          the other eggs.
-- Date: 2026-10-17
-- Reverse: DELETE FROM public.shop_items WHERE category = 'pet_egg' AND metadata->>'pet_type' = 'phoenix';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Phoenix Egg',
       'A warm red-and-gold egg that never quite cools, smuggled in by the Shadowy Dealer. Hatches in 24 hours.',
       2000, 'pet_egg', jsonb_build_object('pet_type', 'phoenix'), 4, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'pet_egg' AND metadata->>'pet_type' = 'phoenix');
