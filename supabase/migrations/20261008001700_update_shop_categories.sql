-- Migration: Update shop_items to support new feature categories
-- Purpose: Add categories for pets, backdrops, houses, and building items
-- Date: 2026-10-07

-- Add CHECK constraint for new categories if not already present
-- (This ensures category validation at DB level)

-- The shop_items table already exists, just document the new valid categories:
-- Existing: 'nameplate_effect', 'roster_border', 'sticker'
-- New: 'pet_egg', 'backdrop', 'house_tier', 'house_addition', 'food', 'wood'

-- Create comment documenting valid categories
COMMENT ON COLUMN public.shop_items.category IS
'Valid categories: nameplate_effect, roster_border, sticker, pet_egg, backdrop, house_tier, house_addition, food, wood';

-- Add sample shop items for new features (optional - for reference)
-- These will be added via frontend, but documenting the expected structure:

-- Pet Eggs (example):
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Dragon Egg', 'A mysterious dragon egg that will hatch in 24 hours', 200, 'pet_egg', '{"pet_type": "dragon", "rarity": "rare"}', 1, true);

-- Backdrops (example):
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Stormwind', 'A backdrop of the bustling city of Stormwind', 100, 'backdrop', '{"image_url": "stormwind.jpg", "location": "Stormwind"}', 1, true);

-- House Tiers (example - tier 1 and upgrades):
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Cozy Cottage Tier 1', 'A modest cottage to call your own', 0, 'house_tier', '{"tier": 1, "wood_cost": 0}', 1, true);
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Cozy Cottage Tier 2', 'Upgraded to a larger home', 500, 'house_tier', '{"tier": 2, "wood_cost": 500}', 2, true);

-- House Additions (example):
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Wooden Fence', 'A sturdy wooden fence for your property', 100, 'house_addition', '{"type": "fence", "wood_cost": 100}', 1, true);

-- Food & Wood resources (example):
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Food Bundle (10)', 'Buy 10 food to feed your pets', 50, 'food', '{"amount": 10}', 1, true);
-- INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
-- VALUES ('Wood Bundle (50)', 'Buy 50 wood for construction', 75, 'wood', '{"amount": 50}', 1, true);
