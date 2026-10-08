-- Migration: Create house_additions table
-- Purpose: Track user's purchased house additions and which are currently active
-- Date: 2026-10-07

CREATE TABLE public.house_additions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  addition_item_id UUID NOT NULL, -- FK to shop_items where category='house_addition'
  is_active BOOLEAN DEFAULT true, -- User can toggle on/off
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

  CONSTRAINT unique_addition_per_user UNIQUE(user_id, addition_item_id)
);

-- Enable RLS
ALTER TABLE public.house_additions ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX idx_house_additions_user ON public.house_additions(user_id);
CREATE INDEX idx_house_additions_item ON public.house_additions(addition_item_id);
CREATE INDEX idx_house_additions_active ON public.house_additions(user_id, is_active);

-- Policy 1: Anyone can view house additions
CREATE POLICY "Public can view house additions"
  ON public.house_additions FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Users can update their own additions (toggle active state)
CREATE POLICY "Users can update own additions"
  ON public.house_additions FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Policy 3: Users can insert additions when they purchase
CREATE POLICY "Users can add own additions"
  ON public.house_additions FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());
