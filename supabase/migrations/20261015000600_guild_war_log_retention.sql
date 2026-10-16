-- Migration: trim old Guild War move logs
-- Purpose: each war's move-by-move log (guild_war_log) is a few MB. For wars that finished more than two months
--   ago, delete that log nightly. Kept forever: the war row itself (final board, result, each player's stats) and
--   every medal (guild_war_medals).
-- Date: 2026-10-15
-- Reverse: SELECT cron.unschedule('trim-old-war-logs'); DROP FUNCTION trim_old_war_logs(INTEGER);

CREATE OR REPLACE FUNCTION public.trim_old_war_logs(p_days INTEGER DEFAULT 60)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
  DELETE FROM guild_war_log l
  USING guild_war_games g
  WHERE l.game_id = g.id
    AND NOT g.active
    AND g.state->>'phase' = 'ended'
    AND g.updated_at < now() - make_interval(days => p_days);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
REVOKE EXECUTE ON FUNCTION public.trim_old_war_logs(INTEGER) FROM PUBLIC, anon, authenticated;

-- nightly at 11:00 UTC (3-4 AM Pacific), after the game-log rollup
DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'trim-old-war-logs';
  PERFORM cron.schedule('trim-old-war-logs', '0 11 * * *', 'SELECT public.trim_old_war_logs(60);');
END $$;
