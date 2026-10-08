-- Migration: Create house table
-- Purpose: Track user's house tier and active backdrop selection
-- Date: 2026-10-07

CREATE TABLE public.house (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  backdrop_id UUID, -- FK to shop_items where category='backdrop'
  house_tier INTEGER DEFAULT 1, -- 1, 2, or 3
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

  CONSTRAINT valid_tier CHECK (house_tier >= 1 AND house_tier <= 3)
);

-- Enable RLS
ALTER TABLE public.house ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX idx_house_backdrop ON public.house(backdrop_id);

-- Policy 1: Anyone can view house data
CREATE POLICY "Public can view house"
  ON public.house FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Users can update their own house
CREATE POLICY "Users can update own house"
  ON public.house FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Policy 3: Users can insert their own house (auto-created on first purchase)
CREATE POLICY "Users can create own house"
  ON public.house FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());
