-- Migration: Add public function for upcoming events
-- Purpose: Allow unauthorized users to read upcoming events (30 days) for the Coming Up panel on entry page
-- Date: 2026-10-07

CREATE OR REPLACE FUNCTION public.get_upcoming_events(p_limit integer DEFAULT 5)
RETURNS TABLE (
  id uuid,
  title text,
  date date,
  time text,
  instance text,
  notes text
) AS $$
DECLARE
  v_today date;
  v_thirty_days_out date;
BEGIN
  v_today := CURRENT_DATE;
  v_thirty_days_out := CURRENT_DATE + INTERVAL '30 days';

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.time,
    e.instance,
    e.notes
  FROM public.events e
  WHERE e.date >= v_today
    AND e.date <= v_thirty_days_out
  ORDER BY e.date ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to anonymous users
GRANT EXECUTE ON FUNCTION public.get_upcoming_events(integer) TO anon;
GRANT EXECUTE ON FUNCTION public.get_upcoming_events(integer) TO authenticated;

-- Add RLS policy to allow public read access to events
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_public_read_events" ON public.events
  FOR SELECT
  USING (true);

GRANT SELECT ON public.events TO anon;
GRANT SELECT ON public.events TO authenticated;
