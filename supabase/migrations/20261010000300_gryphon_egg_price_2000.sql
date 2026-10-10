-- Migration: Gryphon Egg price + description
-- Purpose: Raise the Gryphon Egg to 2000 gold and mention the Shadowy Dealer.
--          purchase_pet_egg reads the price from shop_items, so this is the only change needed.
-- Date: 2026-10-10
-- Reverse: UPDATE public.shop_items SET cost = 700,
--          description = 'A majestic gryphon egg. Will hatch in 24 hours.'
--          WHERE category = 'pet_egg' AND name = 'Gryphon Egg';

UPDATE public.shop_items
SET cost = 2000,
    description = 'A majestic gryphon egg, smuggled in by the Shadowy Dealer. Hatches in 24 hours.'
WHERE category = 'pet_egg'
  AND name = 'Gryphon Egg';
