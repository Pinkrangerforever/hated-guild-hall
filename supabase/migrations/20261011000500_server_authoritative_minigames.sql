-- Migration: Server-authoritative mini-games + real anti-cheat
-- Purpose:
--   1) The SERVER decides wins. claim_sparkle_gold now picks each game's parameters (fishing zone,
--      murloc count, blacksmith rhythm) and stores them; resolve_sparkle_event ignores the client's
--      "won" and replays the client's click timings against those parameters.
--   2) Rate limits a script can't skip: >= 20 s between sparkle claims, and a daily mini-game cap
--      (1500 gold / 60 food per day, America/Denver). Past the cap games still play but pay nothing.
--   3) Anti-cheat that records: no more RAISE-after-logging (which rolled the log back). Flags add
--      points via add_cheat_points(); 100+ points = automatic SOFT_BAN (plays, earns nothing).
--      Statuses: CLEAN, WATCH, UNDER_REVIEW, SOFT_BAN, BANNED (BANNED earns nothing either).
--   4) Admin (protected Raid Leader only): admin_cheat_overview() and admin_set_cheat_status().
--   5) Hygiene: revoke leftover TRUNCATE etc. on anti-cheat tables, drop duplicate indexes,
--      per-user cleanup of old pending games / claims.
-- Date: 2026-10-11
-- Reverse: re-create claim_sparkle_gold / resolve_sparkle_event from 20261011000100 and the
--          2026-10-10 schema backup; drop the new functions and columns.

-- ============================================================================
-- 0) Schema tweaks
-- ============================================================================
ALTER TABLE public.user_cheat_scores DROP CONSTRAINT IF EXISTS user_cheat_scores_status_check;
ALTER TABLE public.user_cheat_scores ADD CONSTRAINT user_cheat_scores_status_check
  CHECK (status = ANY (ARRAY['CLEAN', 'WATCH', 'UNDER_REVIEW', 'SOFT_BAN', 'BANNED']));
ALTER TABLE public.user_cheat_scores ADD COLUMN IF NOT EXISTS status_set_by UUID;
ALTER TABLE public.user_cheat_scores ADD COLUMN IF NOT EXISTS status_note TEXT;

ALTER TABLE public.game_events ADD COLUMN IF NOT EXISTS food_awarded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.game_events ADD COLUMN IF NOT EXISTS reaction_ms INTEGER;       -- fastest human-facing reaction in the game
ALTER TABLE public.game_events ADD COLUMN IF NOT EXISTS client_claimed_win BOOLEAN; -- what the browser said, for comparison

ALTER TABLE public.pending_games ADD COLUMN IF NOT EXISTS params JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Leftover table privileges (PostgREST can't use these, but they should never have been granted)
REVOKE ALL ON public.pending_games, public.game_events, public.cheat_audit_log,
              public.user_cheat_scores, public.sparkle_claims FROM anon, authenticated;
REVOKE ALL ON public.cheat_suspects FROM anon, authenticated;

DROP INDEX IF EXISTS public.idx_game_events_user_created;  -- same as idx_game_events_user
DROP INDEX IF EXISTS public.idx_pending_user_created;      -- same as idx_pending_games_user

-- ============================================================================
-- 1) Helpers
-- ============================================================================
-- Add cheat points and move the status along (manual WATCH/BANNED decisions are kept)
CREATE OR REPLACE FUNCTION public.add_cheat_points(p_user_id UUID, p_points INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_points <= 0 THEN RETURN; END IF;
  INSERT INTO user_cheat_scores (user_id, total_points, flag_count, status, last_flagged_at, updated_at)
  VALUES (p_user_id, p_points, 1,
          CASE WHEN p_points >= 100 THEN 'SOFT_BAN' WHEN p_points >= 50 THEN 'UNDER_REVIEW' ELSE 'CLEAN' END,
          NOW(), NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    total_points = user_cheat_scores.total_points + p_points,
    flag_count = user_cheat_scores.flag_count + 1,
    status = CASE
      WHEN user_cheat_scores.status = 'BANNED' THEN 'BANNED'
      WHEN user_cheat_scores.total_points + p_points >= 100 THEN 'SOFT_BAN'
      WHEN user_cheat_scores.status = 'WATCH' THEN 'WATCH'
      WHEN user_cheat_scores.total_points + p_points >= 50 THEN 'UNDER_REVIEW'
      ELSE user_cheat_scores.status
    END,
    last_flagged_at = NOW(),
    updated_at = NOW();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.add_cheat_points(UUID, INTEGER) FROM PUBLIC, anon, authenticated;

-- Today's mini-game earnings (gold, food) since midnight America/Denver
CREATE OR REPLACE FUNCTION public.minigame_earned_today(p_user_id UUID)
RETURNS TABLE (gold INTEGER, food INTEGER)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(ge.gold_awarded), 0)::INTEGER, COALESCE(SUM(ge.food_awarded), 0)::INTEGER
  FROM game_events ge
  WHERE ge.user_id = p_user_id
    AND ge.created_at >= (date_trunc('day', now() AT TIME ZONE 'America/Denver') AT TIME ZONE 'America/Denver') AT TIME ZONE 'UTC';
$$;
REVOKE EXECUTE ON FUNCTION public.minigame_earned_today(UUID) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 2) Start a sparkle: cooldown, ban check, server-chosen game parameters
-- ============================================================================
CREATE OR REPLACE FUNCTION public.claim_sparkle_gold()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_status TEXT;
  v_last TIMESTAMP;
  v_claim_count INT;
  v_event_type TEXT;
  v_rand FLOAT;
  v_params JSONB;
  v_pending_id UUID;
  v_challenge TEXT;
  v_gold INT := 0;
  v_earned RECORD;
  v_capped BOOLEAN := false;
  v_intervals FLOAT[];
  v_stddev FLOAT;
  c_cooldown CONSTANT INTERVAL := INTERVAL '20 seconds';
  c_gold_cap CONSTANT INT := 1500;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Housekeeping for this player (keeps the tables small without a cron job)
  DELETE FROM pending_games WHERE user_id = v_user_id AND created_at < NOW() - INTERVAL '2 days';
  DELETE FROM sparkle_claims WHERE user_id = v_user_id AND created_at < NOW() - INTERVAL '2 days';

  SELECT MAX(created_at) INTO v_last FROM sparkle_claims WHERE user_id = v_user_id;
  IF v_last IS NOT NULL AND v_last > NOW() - c_cooldown THEN
    -- Sparkles spawn every 30-50 s, so a real player can't get here; a script can
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CLAIM_TOO_SOON', ARRAY['TOO_SOON'], 'LOW',
            jsonb_build_object('seconds_since_last', EXTRACT(EPOCH FROM (NOW() - v_last))));
    PERFORM add_cheat_points(v_user_id, 2);
    RETURN jsonb_build_object('success', false, 'error', 'too_soon');
  END IF;

  SELECT COUNT(*) INTO v_claim_count FROM sparkle_claims
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_claim_count >= 150 THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CLAIM_SPAM', ARRAY['SPAM'], 'MEDIUM', jsonb_build_object('claims_per_hour', v_claim_count));
    PERFORM add_cheat_points(v_user_id, 10);
    RETURN jsonb_build_object('success', false, 'error', 'rate_limited');
  END IF;

  -- Robotic rhythm: the last 10 claims spaced almost exactly evenly
  SELECT array_agg(gap) INTO v_intervals FROM (
    SELECT EXTRACT(EPOCH FROM (created_at - LAG(created_at) OVER (ORDER BY created_at)))::FLOAT AS gap
    FROM (SELECT created_at FROM sparkle_claims WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 11) last11
  ) g WHERE gap IS NOT NULL AND gap < 300;
  IF array_length(v_intervals, 1) >= 10 THEN
    SELECT stddev_pop(x) INTO v_stddev FROM unnest(v_intervals) x;
    IF v_stddev < 0.4 THEN
      INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
      VALUES (v_user_id, 'ROBOTIC_RHYTHM', ARRAY['ROBOTIC_INTERVALS'], 'MEDIUM', jsonb_build_object('stddev_s', v_stddev));
      PERFORM add_cheat_points(v_user_id, 20);
    END IF;
  END IF;

  INSERT INTO sparkle_claims (user_id) VALUES (v_user_id);
  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;

  v_rand := random();
  v_event_type := CASE WHEN v_rand < 0.25 THEN 'fishing' WHEN v_rand < 0.5 THEN 'blacksmith'
                       WHEN v_rand < 0.75 THEN 'murloc' ELSE NULL END;

  IF v_event_type IS NULL THEN
    -- Plain sparkle: small gold, unless banned or capped
    SELECT * INTO v_earned FROM minigame_earned_today(v_user_id);
    IF v_status IN ('SOFT_BAN', 'BANNED') THEN
      v_gold := 0;
    ELSIF v_earned.gold >= c_gold_cap THEN
      v_gold := 0; v_capped := true;
    ELSE
      v_gold := LEAST(8 + (random() * 7)::INT, c_gold_cap - v_earned.gold);
      UPDATE profiles SET gold = COALESCE(gold, 0) + v_gold,
                          gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold
      WHERE id = v_user_id;
    END IF;
    INSERT INTO game_events (user_id, game_type, won, gold_awarded, flags, severity)
    VALUES (v_user_id, 'normal_claim', TRUE, v_gold, ARRAY[]::TEXT[], 'LOW');
    RETURN jsonb_build_object('success', true, 'event', NULL, 'awarded', v_gold, 'capped', v_capped,
                              'total', (SELECT gold FROM profiles WHERE id = v_user_id));
  END IF;

  v_params := CASE v_event_type
    WHEN 'fishing' THEN jsonb_build_object(
      'zone_start', -80 + floor(random() * 134)::INT, 'zone_width', 26, 'sweep_ms', 1400, 'game_ms', 6000, 'idle_ms', 6000)
    WHEN 'murloc' THEN jsonb_build_object(
      'count', 3 + floor(random() * 3)::INT, 'duration_ms', 4500)
    ELSE jsonb_build_object(
      'cycle_ms', 1400, 'hit_window', 0.15, 'hits_needed', 3, 'max_attempts', 5, 'game_ms', 10000)
  END;

  v_challenge := gen_random_challenge(32);
  INSERT INTO pending_games (user_id, event_type, challenge, challenge_expires, created_at_epoch, params)
  VALUES (v_user_id, v_event_type, v_challenge, NOW() + INTERVAL '30 seconds',
          (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT, v_params)
  RETURNING id INTO v_pending_id;

  RETURN jsonb_build_object('success', true, 'pending_id', v_pending_id, 'challenge', v_challenge,
                            'event', v_event_type, 'params', v_params, 'nonce', gen_random_uuid(), 'awarded', 0);
END;
$$;

-- ============================================================================
-- 3) Finish a game: the server replays the clicks and decides
--    p_client_timings: ms since the game's own start, per scored click
--      fishing    [ms to click the pond, ms after the gauge appeared]
--      murloc     [ms of each murloc hit]
--      blacksmith [ms of each counted hammer click]
-- ============================================================================
CREATE OR REPLACE FUNCTION public.resolve_sparkle_event(
  p_pending_id uuid, p_won boolean, p_challenge text, p_signature text, p_nonce uuid,
  p_client_time_ms bigint, p_client_timings jsonb, p_payload text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_rec RECORD;
  v_p JSONB;
  v_t INT[];
  v_n INT;
  v_won BOOLEAN := false;
  v_reaction INT;
  v_flags TEXT[] := ARRAY[]::TEXT[];
  v_points INT := 0;
  v_server_elapsed BIGINT;
  v_status TEXT;
  v_earned RECORD;
  v_gold INT := 0;
  v_food INT := 0;
  v_capped BOOLEAN := false;
  -- fishing
  v_pos FLOAT; v_angle FLOAT; v_zone_start FLOAT; v_zone_end FLOAT;
  -- blacksmith
  v_hits INT := 0; v_attempts INT := 0; v_last_cycle INT := -1; v_cycle INT; v_phase FLOAT; i INT;
  c_gold_cap CONSTANT INT := 1500;
  c_food_cap CONSTANT INT := 60;
  c_min_reaction CONSTANT INT := 120; -- ms; faster than any human reaction
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_rec FROM pending_games WHERE id = p_pending_id FOR UPDATE;
  IF v_rec.id IS NULL OR v_rec.user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_rec.won IS NOT NULL THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'REPLAY_ATTEMPT', ARRAY['REPLAY'], 'HIGH', jsonb_build_object('pending_id', p_pending_id));
    PERFORM add_cheat_points(v_user_id, 30);
    RETURN jsonb_build_object('success', false, 'error', 'already_resolved');
  END IF;

  -- Integrity: the stored challenge must sign the payload (a hand-edited request fails here)
  IF p_challenge IS DISTINCT FROM v_rec.challenge
     OR encode(extensions.hmac(p_payload, v_rec.challenge, 'sha256'), 'hex') IS DISTINCT FROM p_signature THEN
    v_flags := array_append(v_flags, 'SIGNATURE_MISMATCH'); v_points := v_points + 40;
  END IF;

  v_server_elapsed := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - v_rec.created_at_epoch;
  IF v_rec.challenge_expires < NOW() THEN
    v_flags := array_append(v_flags, 'EXPIRED');
  END IF;

  -- Click timings as integers
  SELECT COALESCE(array_agg(round(x::numeric)::INT ORDER BY ord), ARRAY[]::INT[]) INTO v_t
  FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_client_timings) = 'array' THEN p_client_timings ELSE '[]'::jsonb END)
       WITH ORDINALITY AS e(x, ord)
  WHERE x ~ '^-?[0-9]+(\.[0-9]+)?$';
  v_n := COALESCE(array_length(v_t, 1), 0);
  v_p := v_rec.params;

  IF v_rec.event_type = 'fishing' AND v_n >= 2 THEN
    v_reaction := v_t[2]; -- gauge click after the gauge appears
    v_zone_start := (v_p->>'zone_start')::FLOAT;
    v_zone_end := v_zone_start + (v_p->>'zone_width')::FLOAT;
    v_pos := (v_t[2] % (v_p->>'sweep_ms')::INT)::FLOAT / (v_p->>'sweep_ms')::FLOAT;
    v_angle := CASE WHEN v_pos < 0.5 THEN -90 + (v_pos / 0.5) * 180 ELSE 90 - ((v_pos - 0.5) / 0.5) * 180 END;
    v_won := v_t[2] <= (v_p->>'game_ms')::INT AND v_angle BETWEEN v_zone_start - 2 AND v_zone_end + 2;
    IF v_t[1] + v_t[2] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'murloc' AND v_n >= 1 THEN
    v_reaction := v_t[1];
    v_won := v_n = (v_p->>'count')::INT AND v_t[v_n] <= (v_p->>'duration_ms')::INT + 150;
    FOR i IN 2..v_n LOOP
      IF v_t[i] < v_t[i - 1] THEN v_won := false; END IF;
      IF v_t[i] - v_t[i - 1] < 60 THEN
        v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; EXIT;
      END IF;
    END LOOP;
    IF v_t[v_n] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'blacksmith' AND v_n >= 1 THEN
    v_reaction := v_t[1];
    FOR i IN 1..v_n LOOP
      EXIT WHEN v_attempts >= (v_p->>'max_attempts')::INT OR v_hits >= (v_p->>'hits_needed')::INT;
      IF v_t[i] > (v_p->>'game_ms')::INT THEN EXIT; END IF;
      v_cycle := v_t[i] / (v_p->>'cycle_ms')::INT;
      IF v_cycle = v_last_cycle THEN CONTINUE; END IF; -- one counted swing per hammer cycle
      v_last_cycle := v_cycle;
      v_phase := (v_t[i] % (v_p->>'cycle_ms')::INT)::FLOAT / (v_p->>'cycle_ms')::FLOAT;
      v_attempts := v_attempts + 1;
      IF v_phase < (v_p->>'hit_window')::FLOAT THEN v_hits := v_hits + 1; END IF;
    END LOOP;
    v_won := v_hits >= (v_p->>'hits_needed')::INT;
    IF v_t[v_n] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;
  END IF;

  -- (blacksmith's first swing can legitimately land in the opening window, so it isn't checked)
  IF v_rec.event_type <> 'blacksmith' AND v_reaction IS NOT NULL AND v_reaction < c_min_reaction THEN
    v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; v_won := false;
  END IF;
  -- The browser claims a win the clicks don't support: a tampered or scripted client
  IF p_won AND NOT v_won AND NOT ('SUPERHUMAN_SPEED' = ANY(v_flags)) THEN
    v_flags := array_append(v_flags, 'CLIENT_WIN_MISMATCH'); v_points := v_points + 10;
  END IF;
  IF 'EXPIRED' = ANY(v_flags) OR 'SIGNATURE_MISMATCH' = ANY(v_flags) THEN v_won := false; END IF;

  UPDATE pending_games SET won = v_won, resolved_at = NOW() WHERE id = p_pending_id;

  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;
  IF v_won AND COALESCE(v_status, 'CLEAN') NOT IN ('SOFT_BAN', 'BANNED') THEN
    SELECT * INTO v_earned FROM minigame_earned_today(v_user_id);
    v_gold := CASE v_rec.event_type
      WHEN 'fishing' THEN 25 + (random() * 10)::INT
      WHEN 'murloc' THEN 15 + (random() * 10)::INT
      ELSE 20 + (random() * 10)::INT END;
    v_food := CASE WHEN v_rec.event_type IN ('murloc', 'fishing') THEN 2 + floor(random() * 3)::INT ELSE 0 END;
    IF v_earned.gold + v_gold > c_gold_cap THEN v_gold := GREATEST(c_gold_cap - v_earned.gold, 0); v_capped := true; END IF;
    IF v_earned.food + v_food > c_food_cap THEN v_food := GREATEST(c_food_cap - v_earned.food, 0); v_capped := true; END IF;
    IF v_gold > 0 OR v_food > 0 THEN
      UPDATE profiles
      SET gold = COALESCE(gold, 0) + v_gold, gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold,
          food = COALESCE(food, 0) + v_food, food_earned_total = COALESCE(food_earned_total, 0) + v_food
      WHERE id = v_user_id;
    END IF;
  END IF;

  INSERT INTO game_events (user_id, pending_id, game_type, won, gold_awarded, food_awarded, client_timings,
                           client_submit_time_ms, flags, severity, reaction_ms, client_claimed_win, cheat_score_delta)
  VALUES (v_user_id, p_pending_id, v_rec.event_type, v_won, v_gold, v_food, p_client_timings, p_client_time_ms,
          v_flags, CASE WHEN v_points >= 30 THEN 'HIGH' WHEN v_points > 0 THEN 'MEDIUM' ELSE 'LOW' END,
          v_reaction, p_won, v_points);

  IF v_points > 0 THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'GAME_FLAGGED', v_flags, CASE WHEN v_points >= 30 THEN 'HIGH' ELSE 'MEDIUM' END,
            jsonb_build_object('pending_id', p_pending_id, 'game', v_rec.event_type, 'timings', p_client_timings,
                               'reaction_ms', v_reaction, 'server_elapsed_ms', v_server_elapsed));
    PERFORM add_cheat_points(v_user_id, v_points);
  END IF;

  RETURN jsonb_build_object(
    'success', v_won, 'won', v_won, 'capped', v_capped,
    'awarded', v_gold, 'food_awarded', v_food,
    'total', (SELECT gold FROM profiles WHERE id = v_user_id),
    'food_total', (SELECT food FROM profiles WHERE id = v_user_id));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_sparkle_gold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_sparkle_gold() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) TO authenticated;

-- ============================================================================
-- 4) Admin: suspect list + actions (protected Raid Leader account only)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_cheat_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  WITH stats AS (
    SELECT ge.user_id,
           COUNT(*) FILTER (WHERE ge.game_type <> 'normal_claim') AS games_7d,
           COUNT(*) FILTER (WHERE ge.game_type <> 'normal_claim' AND ge.won) AS wins_7d,
           COUNT(*) FILTER (WHERE ge.created_at > NOW() - INTERVAL '1 day') AS events_24h,
           COUNT(DISTINCT date_trunc('hour', ge.created_at)) FILTER (WHERE ge.created_at > NOW() - INTERVAL '1 day') AS active_hours_24h,
           SUM(ge.gold_awarded) FILTER (WHERE ge.created_at > NOW() - INTERVAL '1 day') AS gold_24h,
           MIN(ge.reaction_ms) AS fastest_reaction_ms,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY ge.reaction_ms) AS median_reaction_ms
    FROM game_events ge
    WHERE ge.created_at > NOW() - INTERVAL '7 days'
    GROUP BY ge.user_id
  ), people AS (
    SELECT pr.id AS user_id, pr.character_name, pr.discord_username,
           COALESCE(cs.total_points, 0) AS points, COALESCE(cs.flag_count, 0) AS flag_count,
           COALESCE(cs.status, 'CLEAN') AS status, cs.status_note, cs.last_flagged_at,
           COALESCE(st.games_7d, 0) AS games_7d,
           CASE WHEN COALESCE(st.games_7d, 0) > 0 THEN round(100.0 * st.wins_7d / st.games_7d, 1) END AS win_pct_7d,
           COALESCE(st.events_24h, 0) AS events_24h, COALESCE(st.active_hours_24h, 0) AS active_hours_24h,
           COALESCE(st.gold_24h, 0) AS gold_24h, st.fastest_reaction_ms, round(st.median_reaction_ms::numeric) AS median_reaction_ms
    FROM profiles pr
    LEFT JOIN user_cheat_scores cs ON cs.user_id = pr.id
    LEFT JOIN stats st ON st.user_id = pr.id
  )
  SELECT jsonb_build_object(
    'suspects', COALESCE((
      SELECT jsonb_agg(to_jsonb(pe) ORDER BY pe.points DESC, pe.gold_24h DESC)
      FROM people pe
      WHERE pe.points > 0 OR pe.status <> 'CLEAN'
         OR (pe.games_7d >= 20 AND pe.win_pct_7d >= 95)       -- near-perfect over many games
         OR pe.active_hours_24h >= 18                          -- playing around the clock
         OR (pe.median_reaction_ms IS NOT NULL AND pe.median_reaction_ms < 250)
    ), '[]'::jsonb),
    'top_earners_24h', COALESCE((
      SELECT jsonb_agg(to_jsonb(t)) FROM (
        SELECT pe.user_id, pe.character_name, pe.gold_24h, pe.events_24h, pe.win_pct_7d, pe.status
        FROM people pe WHERE pe.gold_24h > 0 ORDER BY pe.gold_24h DESC LIMIT 10) t
    ), '[]'::jsonb),
    'audit_log', COALESCE((
      SELECT jsonb_agg(to_jsonb(a)) FROM (
        SELECT l.id, l.user_id, pr.character_name, l.event_type, l.flags, l.severity, l.details, l.created_at, l.resolution
        FROM cheat_audit_log l LEFT JOIN profiles pr ON pr.id = l.user_id
        ORDER BY l.created_at DESC LIMIT 40) a
    ), '[]'::jsonb),
    'flagged_games', COALESCE((
      SELECT jsonb_agg(to_jsonb(g)) FROM (
        SELECT ge.id, ge.user_id, pr.character_name, ge.game_type, ge.won, ge.client_claimed_win, ge.gold_awarded,
               ge.flags, ge.reaction_ms, ge.client_timings, ge.created_at
        FROM game_events ge LEFT JOIN profiles pr ON pr.id = ge.user_id
        WHERE ge.flags <> ARRAY[]::TEXT[] ORDER BY ge.created_at DESC LIMIT 40) g
    ), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_cheat_status(p_user_id UUID, p_status TEXT, p_note TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID := auth.uid();
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = v_admin), false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF p_status NOT IN ('CLEAN', 'WATCH', 'SOFT_BAN', 'BANNED') THEN
    RETURN jsonb_build_object('success', false, 'error', 'bad_status');
  END IF;

  INSERT INTO user_cheat_scores (user_id, total_points, flag_count, status, status_set_by, status_note, updated_at)
  VALUES (p_user_id, 0, 0, p_status, v_admin, p_note, NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    status = p_status,
    total_points = CASE WHEN p_status = 'CLEAN' THEN 0 ELSE user_cheat_scores.total_points END, -- clearing resets points
    status_set_by = v_admin, status_note = p_note, updated_at = NOW();

  INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details, reviewed_by, review_notes, resolution)
  VALUES (p_user_id, 'ADMIN_STATUS_' || p_status, ARRAY['ADMIN'], 'LOW', jsonb_build_object('status', p_status),
          v_admin, p_note,
          CASE p_status WHEN 'CLEAN' THEN 'FALSE_POSITIVE' WHEN 'WATCH' THEN 'WARNING_ISSUED' ELSE 'CONFIRMED_CHEAT' END);
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_cheat_overview() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_cheat_status(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cheat_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_cheat_status(UUID, TEXT, TEXT) TO authenticated;
