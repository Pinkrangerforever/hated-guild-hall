-- Migration: Add public function for upcoming events
-- Purpose: Allow unauthorized users to read upcoming events (30 days) for the Coming Up panel on entry page
-- Date: 2026-10-07

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "allow_public_read_events" ON public.events;
DROP POLICY IF EXISTS "allow_anonymous_read_events" ON public.events;

-- Enable RLS on events table
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Create policy allowing anyone to read events (anon role is unauthenticated)
CREATE POLICY "allow_anonymous_read_events" ON public.events
  FOR SELECT
  TO anon
  USING (true);

-- Also allow authenticated users
CREATE POLICY "allow_authenticated_read_events" ON public.events
  FOR SELECT
  TO authenticated
  USING (true);

-- Grant permissions on the table to both roles
GRANT SELECT ON public.events TO anon;
GRANT SELECT ON public.events TO authenticated;

-- Create helper function for upcoming events (optional, can be used instead of direct table access)
CREATE OR REPLACE FUNCTION public.get_upcoming_events(p_limit integer DEFAULT 5)
RETURNS TABLE (
  id uuid,
  title text,
  date date,
  time text,
  instance text,
  notes text
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.time,
    e.instance,
    e.notes
  FROM public.events e
  WHERE e.date >= CURRENT_DATE
    AND e.date <= (CURRENT_DATE + INTERVAL '30 days')
  ORDER BY e.date ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute on function to both roles
GRANT EXECUTE ON FUNCTION public.get_upcoming_events(integer) TO anon;
GRANT EXECUTE ON FUNCTION public.get_upcoming_events(integer) TO authenticated;
