-- Migration: Add pet eggs to shop
-- Purpose: Add purchasable pet eggs (only visible if user has trader access)
-- Date: 2026-10-09

-- Drop the existing category check constraint (it's too restrictive for new pet_egg category)
ALTER TABLE public.shop_items DROP CONSTRAINT IF EXISTS shop_items_category_check CASCADE;

-- Insert Gryphon pet egg
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
