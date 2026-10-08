-- Migration: Create purchase_log table for tracking all purchases
-- Purpose: Track all user purchases (shop items, dealer access, resources, etc)
-- Date: 2026-10-08

CREATE TABLE public.purchase_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id UUID, -- FK to shop_items if applicable (nullable for non-shop purchases)
  purchase_type TEXT NOT NULL, -- 'shop_item', 'dealer_access', 'food_bundle', etc.
  amount INTEGER, -- Gold spent
  description TEXT, -- 'Dealer Access: 3000g', 'Dragon Egg: 200g', etc.
  metadata JSONB, -- Extra data like {pet_type: 'dragon'} or {item_name: 'Dealer Access'}
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

  CONSTRAINT valid_type CHECK (purchase_type IN ('shop_item', 'dealer_access', 'food_bundle', 'wood_bundle', 'nameplate_effect', 'roster_border', 'sticker', 'backdrop', 'house_addition'))
);

-- Enable RLS
ALTER TABLE public.purchase_log ENABLE ROW LEVEL SECURITY;

-- Create indexes for performance
CREATE INDEX idx_purchase_log_user ON public.purchase_log(user_id);
CREATE INDEX idx_purchase_log_type ON public.purchase_log(purchase_type);
CREATE INDEX idx_purchase_log_date ON public.purchase_log(purchased_at);

-- Policy 1: Users can view their own purchases
CREATE POLICY "Users can view own purchases"
  ON public.purchase_log FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Policy 2: System RPC only can insert (no direct client inserts)
-- (Purchases are logged via RPC functions, not from frontend)
