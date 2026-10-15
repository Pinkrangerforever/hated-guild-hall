-- Migration: the Guild War clock
-- Purpose: every 5 minutes, nudge the `war` Edge Function with { action: 'tick' } so the war moves on by itself:
--   the Monday 00:00 PT start, each dawn (and 11:59pm autopilot), the Sunday 8pm end, and the next week's sign-ups.
--   'tick' only does what the clock already says should have happened, so it is safe for anyone to call.
--   The function's address is different on staging and prod, so the function writes its own URL into
--   guild_war_config the first time an admin uses it; until then the job does nothing.
-- Date: 2026-10-15
-- Reverse: SELECT cron.unschedule('guild-war-tick'); DROP FUNCTION guild_war_tick(); DROP TABLE guild_war_config;

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE IF NOT EXISTS public.guild_war_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.guild_war_config ENABLE ROW LEVEL SECURITY;   -- no policies: only the service role (the function) reads or writes it
REVOKE ALL ON public.guild_war_config FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.guild_war_tick()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_url TEXT;
BEGIN
  SELECT value INTO v_url FROM guild_war_config WHERE key = 'tick_url';
  IF v_url IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, body := '{"action":"tick"}'::jsonb, headers := '{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds := 20000);
END $$;
REVOKE EXECUTE ON FUNCTION public.guild_war_tick() FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'guild-war-tick';
  PERFORM cron.schedule('guild-war-tick', '*/5 * * * *', 'SELECT public.guild_war_tick();');
END $$;
