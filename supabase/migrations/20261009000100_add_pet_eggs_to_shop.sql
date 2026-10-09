-- Migration: Add pet eggs to shop
-- Purpose: Add purchasable pet eggs (only visible if user has trader access)
-- Date: 2026-10-09

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
VALUES
  (
    'Dragon Egg',
    'A mysterious dragon egg. Will hatch in 24 hours.',
    500,
    'pet_egg',
    jsonb_build_object('pet_type', 'dragon', 'icon', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/DragonEgg.png'),
    1,
    true
  ),
  (
    'Phoenix Egg',
    'A legendary phoenix egg. Will hatch in 24 hours.',
    600,
    'pet_egg',
    jsonb_build_object('pet_type', 'phoenix', 'icon', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/PhoenixEgg.png'),
    2,
    true
  ),
  (
    'Gryphon Egg',
    'A majestic gryphon egg. Will hatch in 24 hours.',
    700,
    'pet_egg',
    jsonb_build_object('pet_type', 'gryphon', 'icon', 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/GryphonEgg.png'),
    3,
    true
  );
