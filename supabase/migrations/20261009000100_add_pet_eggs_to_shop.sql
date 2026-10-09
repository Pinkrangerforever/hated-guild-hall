-- Migration: Add Gryphon Egg to shop
-- Purpose: Add purchasable Gryphon egg (only visible if user has trader access)
-- Date: 2026-10-09

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES
  (
    'Gryphon Egg',
    'A majestic gryphon egg. Will hatch in 24 hours.',
    700,
    'pet_egg',
    jsonb_build_object('pet_type', 'gryphon'),
    1,
    true
  );
