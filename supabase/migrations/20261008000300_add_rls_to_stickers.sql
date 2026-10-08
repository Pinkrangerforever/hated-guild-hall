-- Migration: Add RLS to stickers table
-- Purpose: Anyone can read stickers, only raid leaders and owners can modify
-- Date: 2026-10-08

-- Enable RLS on stickers
ALTER TABLE public.stickers ENABLE ROW LEVEL SECURITY;

-- Policy 1: Anyone can READ stickers
CREATE POLICY "Public can view stickers"
  ON public.stickers FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Sticker owners or raid leaders can UPDATE (reposition)
CREATE POLICY "Owners and raid leaders can update stickers"
  ON public.stickers FOR UPDATE
  TO authenticated
  USING (
    placed_by_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );

-- Policy 3: Only raid leaders can DELETE stickers
CREATE POLICY "Only raid leaders can delete stickers"
  ON public.stickers FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.protected = true
    )
  );

-- Policy 4: Authenticated users can INSERT (place stickers)
CREATE POLICY "Authenticated users can place stickers"
  ON public.stickers FOR INSERT
  TO authenticated
  WITH CHECK (placed_by_user_id = auth.uid());
