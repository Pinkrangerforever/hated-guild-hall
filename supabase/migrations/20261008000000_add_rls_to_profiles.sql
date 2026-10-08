-- Migration: Add RLS to profiles table with strict gold protection
-- Purpose: Enforce role-based access control at database level
-- Date: 2026-10-08

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policy 1: Public can READ profiles (for leaderboard, roster display)
CREATE POLICY "Public can view profiles"
  ON public.profiles FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Users can UPDATE their own profile, but NOT gold fields
CREATE POLICY "Users can update own profile fields"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND gold_earned_total IS NOT DISTINCT FROM (SELECT gold_earned_total FROM public.profiles WHERE id = auth.uid())
    AND current_gold IS NOT DISTINCT FROM (SELECT current_gold FROM public.profiles WHERE id = auth.uid())
  );

-- Policy 3: ONLY Raid Leaders can modify gold
CREATE POLICY "Only raid leaders can update gold"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );

-- Authenticated users can INSERT (for new profile creation via auth trigger)
CREATE POLICY "Authenticated can insert own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);
