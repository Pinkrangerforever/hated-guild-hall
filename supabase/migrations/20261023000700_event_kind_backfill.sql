-- Migration: give events from before event types their likely type
-- Purpose: events scheduled before 20261023000500 all got type 'event'. The calendar's "Next raid" banner now shows
--          the next Raid-type event, so mark the old ones the way the calendar used to guess: an instance means a
--          raid, a holiday-sounding title means a holiday. Only events created before types existed are touched.
-- Date: 2026-10-23
-- Reverse: none needed (officers can change any event's type on the event itself).

UPDATE public.events SET kind = 'holiday'
WHERE kind = 'event' AND created_at < '2026-10-23 18:00+00'
  AND (title || ' ' || coalesce(instance, '')) ~* '(halloween|christmas|winter veil|hallow|holiday|brewfest|launch|anniversary|party|meetup)';
UPDATE public.events SET kind = 'raid'
WHERE kind = 'event' AND created_at < '2026-10-23 18:00+00' AND coalesce(instance, '') <> '';
