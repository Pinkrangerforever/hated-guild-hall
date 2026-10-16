-- Migration: run the Guild War clock every 10 minutes instead of 5 (half the Edge Function calls; a day change or
-- the war's end can land up to 10 minutes late when nobody is playing - any player action catches up at once).
-- Date: 2026-10-15
DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'guild-war-tick';
  PERFORM cron.schedule('guild-war-tick', '*/10 * * * *', 'SELECT public.guild_war_tick();');
END $$;
