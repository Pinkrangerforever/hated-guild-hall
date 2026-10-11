-- Migration: Sparkle odds - less plain gold, more lumberjack and mining
-- Purpose: plain gold 19% -> 14%, lumberjack 11% -> 13%, mining 11% -> 14% (others unchanged:
--          Hogger 5%, fishing/blacksmith/murloc 14% each, trivia 12%).
-- Date: 2026-10-11
-- Reverse: re-run claim_sparkle_gold from 20261011001800.

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
  v_secret JSONB := '{}'::jsonb;
  v_q RECORD;
  v_order INT[];
  v_gold INT := 0;
  v_earned RECORD;
  v_capped BOOLEAN := false;
  v_mult NUMERIC;
  v_intervals FLOAT[];
  v_stddev FLOAT;
  c_cooldown CONSTANT INTERVAL := INTERVAL '20 seconds';
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
  -- rare 5%, fishing/blacksmith/murloc 14% each, trivia 12%, lumberjack 13%, mining 14%, plain gold 14%
  v_event_type := CASE WHEN v_rand < 0.05 THEN 'rarespawn' WHEN v_rand < 0.19 THEN 'fishing'
                       WHEN v_rand < 0.33 THEN 'blacksmith' WHEN v_rand < 0.47 THEN 'murloc'
                       WHEN v_rand < 0.59 THEN 'trivia' WHEN v_rand < 0.72 THEN 'lumberjack'
                       WHEN v_rand < 0.86 THEN 'mining' ELSE NULL END;

  IF v_event_type IS NULL THEN
    -- Plain sparkle: small gold, unless banned or capped
    SELECT * INTO v_earned FROM minigame_earned_today(v_user_id);
    v_mult := minigame_gold_multiplier(v_earned.gold);
    IF v_status IN ('SOFT_BAN', 'BANNED') THEN
      v_gold := 0;
    ELSE
      v_gold := round((8 + (random() * 7)::INT) * v_mult)::INT;
      v_capped := v_mult < 1;
      UPDATE profiles SET gold = COALESCE(gold, 0) + v_gold,
                          gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold
      WHERE id = v_user_id;
    END IF;
    INSERT INTO game_events (user_id, game_type, won, gold_awarded, flags, severity)
    VALUES (v_user_id, 'normal_claim', TRUE, v_gold, ARRAY[]::TEXT[], 'LOW');
    RETURN jsonb_build_object('success', true, 'event', NULL, 'awarded', v_gold, 'capped', v_capped,
                              'weary', minigame_weary_state(v_user_id),
                              'total', (SELECT gold FROM profiles WHERE id = v_user_id));
  END IF;

  v_params := CASE v_event_type
    WHEN 'fishing' THEN jsonb_build_object(
      -- Stardew-style catch, simulated identically in the browser and in resolve_sparkle_event
      'seed', 1 + floor(random() * 2147483645)::BIGINT,
      'behavior', (ARRAY['mixed', 'mixed', 'dart', 'smooth', 'sinker', 'floater'])[1 + floor(random() * 6)::INT],
      'bar_h', 0.26, 'max_ticks', 1500, 'idle_ms', 8000)
    WHEN 'murloc' THEN jsonb_build_object(
      'count', 3 + floor(random() * 3)::INT, 'duration_ms', 4500)
    WHEN 'blacksmith' THEN jsonb_build_object(
      'cycle_ms', 1400, 'hit_window', 0.15, 'hits_needed', 3, 'max_attempts', 5, 'game_ms', 10000)
    WHEN 'lumberjack' THEN jsonb_build_object(
      'sweep_ms', 1300, 'width', 0.12, 'hits_needed', 3, 'max_attempts', 5, 'game_ms', 9000,
      'notches', jsonb_build_array(round((0.15 + random() * 0.7)::numeric, 3), round((0.15 + random() * 0.7)::numeric, 3),
                                   round((0.15 + random() * 0.7)::numeric, 3)))
    WHEN 'rarespawn' THEN jsonb_build_object(
      'jump_ms', 650, 'duration_ms', 3250, 'radius', 95, 'hits_needed', 3,
      'positions', (SELECT jsonb_agg(jsonb_build_array(120 + floor(random() * 760)::INT, 150 + floor(random() * 700)::INT))
                    FROM generate_series(1, 5)))
    WHEN 'mining' THEN (
      -- Same difficulty for everyone: 3 nodes, 7 swaps at a fixed speed. Swaps are slot pairs.
      SELECT jsonb_build_object('nodes', 3, 'gem_start', floor(random() * 3)::INT, 'reveal_ms', 1600, 'swap_ms', 360,
               'pick_ms', 6000, 'swaps', jsonb_agg(jsonb_build_array(a, b)))
      FROM (SELECT a, (a + 1 + floor(random() * 2)::INT) % 3 AS b
            FROM (SELECT floor(random() * 3)::INT AS a FROM generate_series(1, 7)) x) y)
    ELSE '{}'::jsonb
  END;

  IF v_event_type = 'trivia' THEN
    -- A question this player hasn't seen in their last 40 trivia games, answers shuffled every time.
    -- The browser gets the question and options only; the correct option stays in pending_games.secret.
    SELECT tq.* INTO v_q FROM trivia_questions tq
    WHERE tq.active AND tq.id NOT IN (
      SELECT (pg.secret->>'qid')::INT FROM pending_games pg
      WHERE pg.user_id = v_user_id AND pg.event_type = 'trivia' AND pg.secret ? 'qid'
      ORDER BY pg.created_at DESC LIMIT 40)
    ORDER BY random() LIMIT 1;
    IF v_q.id IS NULL THEN SELECT tq.* INTO v_q FROM trivia_questions tq WHERE tq.active ORDER BY random() LIMIT 1; END IF;
    SELECT array_agg(i ORDER BY random()) INTO v_order FROM generate_series(0, 3) i;
    v_params := jsonb_build_object(
      'question', v_q.question, 'category', v_q.category, 'time_ms', 15000,
      'answers', jsonb_build_array(v_q.answers->v_order[1], v_q.answers->v_order[2], v_q.answers->v_order[3], v_q.answers->v_order[4]));
    v_secret := jsonb_build_object('qid', v_q.id, 'correct', array_position(v_order, v_q.correct_index) - 1);
  END IF;

  v_challenge := gen_random_challenge(32);
  INSERT INTO pending_games (user_id, event_type, challenge, challenge_expires, created_at_epoch, params, secret)
  VALUES (v_user_id, v_event_type, v_challenge, NOW() + INTERVAL '30 seconds',
          (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT, v_params, v_secret)
  RETURNING id INTO v_pending_id;

  RETURN jsonb_build_object('success', true, 'pending_id', v_pending_id, 'challenge', v_challenge,
                            'event', v_event_type, 'params', v_params, 'nonce', gen_random_uuid(), 'awarded', 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_sparkle_gold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_sparkle_gold() TO authenticated;
