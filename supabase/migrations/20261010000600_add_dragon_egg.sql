-- Migration: Dragon Egg in the shop (second pet species)
-- Purpose: purchase_pet_egg matches shop items by metadata.pet_type, so this is all that's needed
--          for players to buy one. Same price as the Gryphon Egg.
-- Date: 2026-10-10
-- Reverse: DELETE FROM public.shop_items WHERE category = 'pet_egg' AND name = 'Dragon Egg';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES (
  'Dragon Egg',
  'A smoldering black dragon egg, smuggled in by the Shadowy Dealer. Hatches in 24 hours.',
  2000,
  'pet_egg',
  jsonb_build_object('pet_type', 'dragon'),
  2,
  true
);
