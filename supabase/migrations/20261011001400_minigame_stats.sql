-- Migration: Mini-game stats for profile pages
-- Purpose: profile_minigame_stats(user) - games played / won per mini-game (recent detail + rolled-up
--          daily summaries), rare elites slain and trivia accuracy. Counts only, readable by signed-in
--          players (it's shown on everyone's profile). No gold amounts.
-- Date: 2026-10-11
-- Reverse: DROP FUNCTION public.profile_minigame_stats(uuid);

CREATE OR REPLACE FUNCTION public.profile_minigame_stats(p_user_id UUID)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH all_games AS (
    SELECT game_type, COUNT(*)::INT AS games, COUNT(*) FILTER (WHERE won)::INT AS wins
    FROM game_events WHERE user_id = p_user_id AND game_type <> 'normal_claim' GROUP BY game_type
    UNION ALL
    SELECT game_type, SUM(games)::INT, SUM(wins)::INT
    FROM game_events_daily WHERE user_id = p_user_id AND game_type <> 'normal_claim' GROUP BY game_type
  ), per_game AS (
    SELECT game_type, SUM(games)::INT AS games, SUM(wins)::INT AS wins FROM all_games GROUP BY game_type
  )
  SELECT jsonb_build_object(
    'games', COALESCE((SELECT jsonb_object_agg(game_type, jsonb_build_object('games', games, 'wins', wins)) FROM per_game), '{}'::jsonb),
    'total_games', COALESCE((SELECT SUM(games) FROM per_game), 0),
    'total_wins', COALESCE((SELECT SUM(wins) FROM per_game), 0),
    'sparkles', (SELECT COUNT(*) FROM game_events WHERE user_id = p_user_id AND game_type = 'normal_claim')
              + COALESCE((SELECT SUM(games) FROM game_events_daily WHERE user_id = p_user_id AND game_type = 'normal_claim'), 0)
  );
$$;
REVOKE EXECUTE ON FUNCTION public.profile_minigame_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.profile_minigame_stats(UUID) TO authenticated;
