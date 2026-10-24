-- Migration: Login Streaks admin report shows the streak actually earned
-- Purpose: the report's "current streak" came from daily_bonus_next(), which is the streak a player's NEXT claim
--          would have - so someone who claimed yesterday showed one more day than they'd claimed (4 with 3 claims).
--          Now: current_streak = days claimed in a row so far (null when the streak is broken), and
--          claimable_today = they can still claim today without breaking it. Read-only report; no gold changes.
-- Date: 2026-10-24
-- Reverse: re-run admin_login_streaks from 20261011000900.

CREATE OR REPLACE FUNCTION public.admin_login_streaks()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(t) ORDER BY t.current_streak DESC NULLS LAST, t.last_claim DESC) FROM (
      SELECT pr.id AS user_id, pr.character_name,
             (SELECT CASE WHEN n.claimed_today THEN n.streak WHEN n.streak > 1 THEN n.streak - 1 END FROM daily_bonus_next(pr.id) n) AS current_streak,
             (SELECT NOT n.claimed_today AND n.streak > 1 FROM daily_bonus_next(pr.id) n) AS claimable_today,
             MAX(dl.day) AS last_claim,
             COUNT(*) FILTER (WHERE dl.day > (now() AT TIME ZONE 'America/Denver')::DATE - 30) AS claims_30d,
             COALESCE(SUM(dl.gold), 0) AS bonus_gold_total
      FROM profiles pr JOIN daily_login_claims dl ON dl.user_id = pr.id
      GROUP BY pr.id, pr.character_name) t
  ), '[]'::jsonb);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_login_streaks() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_login_streaks() TO authenticated;
