-- Migration: Add RLS to events table
-- Purpose: Public can read events (entry page calendar), only officers+ can modify
-- Date: 2026-10-08

-- Enable RLS on events
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Policy 1: Anyone can READ events
CREATE POLICY "Public can view events"
  ON public.events FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy 2: Only officers and raid leaders can CREATE events
CREATE POLICY "Officers and raid leaders can create events"
  ON public.events FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND (p.role = 'officer' OR p.protected = true)
    )
  );

-- Policy 3: Only officers and raid leaders can UPDATE events
CREATE POLICY "Officers and raid leaders can update events"
  ON public.events FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND (p.role = 'officer' OR p.protected = true)
    )
  );

-- Policy 4: Only officers and raid leaders can DELETE events
CREATE POLICY "Officers and raid leaders can delete events"
  ON public.events FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND (p.role = 'officer' OR p.protected = true)
    )
  );
