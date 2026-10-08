-- Migration: Add RLS to guild_layout table
-- Purpose: Everyone can view layout, only raid leaders can modify
-- Date: 2026-10-08

-- Enable RLS on guild_layout
ALTER TABLE public.guild_layout ENABLE ROW LEVEL SECURITY;

-- Policy 1: Anyone can READ guild layout
CREATE POLICY "Public can view guild layout"
  ON public.guild_layout FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Only raid leaders can CREATE layout entries
CREATE POLICY "Only raid leaders can create layout"
  ON public.guild_layout FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );

-- Policy 3: Only raid leaders can UPDATE layout
CREATE POLICY "Only raid leaders can update layout"
  ON public.guild_layout FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );

-- Policy 4: Only raid leaders can DELETE layout
CREATE POLICY "Only raid leaders can delete layout"
  ON public.guild_layout FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );
