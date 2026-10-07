-- Migration: Add test events for staging
-- Purpose: Populate the events table with sample upcoming events for testing
-- Date: 2026-10-07

INSERT INTO public.events (title, date, time, instance, notes) VALUES
  ('Weekly Raid - Monday', '2026-10-13', '7:00 PM', 'Karazhan', 'Bring your A-game'),
  ('Weekly Raid - Wednesday', '2026-10-15', '7:00 PM', 'Serpentshrine', 'Bring your A-game'),
  ('Guild Meeting', '2026-10-20', '8:00 PM', 'Discord', 'Monthly guild discussion'),
  ('Battleground Night', '2026-10-25', '6:00 PM', 'Various', 'All Welcome'),
  ('Weekly Raid - Thursday', '2026-10-22', '7:00 PM', 'Eye of Eternity', 'Bring your A-game');
