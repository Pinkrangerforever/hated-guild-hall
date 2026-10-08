-- Migration: Create pets table
-- Purpose: Store pet data including type, level, exp, hatching status
-- Date: 2026-10-07

CREATE TABLE public.pets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pet_type TEXT NOT NULL, -- 'dragon', 'phoenix', 'wolf', etc.
  name TEXT, -- Null until hatched and named
  level INTEGER DEFAULT 1,
  exp INTEGER DEFAULT 0,
  hatch_time BIGINT NOT NULL, -- Unix timestamp when egg was purchased (24hr from now)
  hatched_at TIMESTAMP WITH TIME ZONE, -- Null until hatched
  status TEXT DEFAULT 'egg', -- 'egg' | 'juvenile' | 'adult' | 'boss'
  last_pet_action_time BIGINT DEFAULT 0, -- Unix timestamp of last pet button click (1hr cooldown)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

  CONSTRAINT valid_status CHECK (status IN ('egg', 'juvenile', 'adult', 'boss')),
  CONSTRAINT unique_active_pet_per_user UNIQUE(user_id) DEFERRABLE INITIALLY DEFERRED
);

-- Enable RLS
ALTER TABLE public.pets ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX idx_pets_user_id ON public.pets(user_id);
CREATE INDEX idx_pets_status ON public.pets(status);

-- Policy 1: Anyone can view pets
CREATE POLICY "Public can view pets"
  ON public.pets FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Users can update their own pets
CREATE POLICY "Users can update own pet"
  ON public.pets FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Policy 3: Authenticated users can insert pets when they purchase eggs
CREATE POLICY "Authenticated can create pets"
  ON public.pets FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());
