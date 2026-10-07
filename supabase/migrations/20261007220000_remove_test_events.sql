-- Migration: Remove test events
-- Purpose: Delete test events added during development. User has their own events.

DELETE FROM public.events
WHERE title IN (
  'Weekly Raid - Monday',
  'Weekly Raid - Wednesday',
  'Guild Meeting',
  'Battleground Night',
  'Weekly Raid - Thursday'
);
