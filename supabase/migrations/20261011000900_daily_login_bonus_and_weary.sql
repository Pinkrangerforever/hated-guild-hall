-- Migration: Daily login bonus (7-day streak) + "Weary" taper on mini-game gold
-- Purpose:
--   * daily_login_claims: one row per player per day (America/Denver). claim_daily_bonus() pays
--     25/35/45/55/65/75 gold on streak days 1-6 and 100 gold + 10 food + 20 wood on day 7, then the
--     cycle repeats. One missed day per 7 days is forgiven (grace); otherwise the streak restarts.
--   * Weary: mini-game gold pays 100% up to 600 earned today, 50% to 1000, 25% to 1300, then 0%
--     until midnight. Replaces the hard 1500 gold cap (the 60 food cap stays). The login bonus
--     doesn't count toward it.
--   * daily_bonus_status() for the page, admin_login_streaks() for the Admin page.
--   * The Gold Ledger includes login bonuses.
-- Date: 2026-10-11
-- Reverse: re-run claim_sparkle_gold / resolve_sparkle_event from 20261011000500 and admin_gold_ledger
--          from 20261011000700; DROP the new functions and daily_login_claims.

CREATE TABLE IF NOT EXISTS public.daily_login_claims (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  streak INTEGER NOT NULL,
  cycle_day INTEGER NOT NULL,
  grace_used BOOLEAN NOT NULL DEFAULT false,
  gold INTEGER NOT NULL DEFAULT 0,
  food INTEGER NOT NULL DEFAULT 0,
  wood INTEGER NOT NULL DEFAULT 0,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day)
);
ALTER TABLE public.daily_login_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.daily_login_claims FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Weary tiers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.minigame_gold_multiplier(p_earned_today INTEGER)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN p_earned_today < 600 THEN 1.0
              WHEN p_earned_today < 1000 THEN 0.5
              WHEN p_earned_today < 1300 THEN 0.25
              ELSE 0 END;
$$;

CREATE OR REPLACE FUNCTION public.minigame_weary_state(p_user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_earned INTEGER;
BEGIN
  SELECT gold INTO v_earned FROM minigame_earned_today(p_user_id);
  v_earned := COALESCE(v_earned, 0);
  RETURN jsonb_build_object(
    'earned', v_earned,
    'multiplier', minigame_gold_multiplier(v_earned),
    'tier', CASE WHEN v_earned < 600 THEN 'rested' WHEN v_earned < 1000 THEN 'tired'
                 WHEN v_earned < 1300 THEN 'weary' ELSE 'exhausted' END,
    'next_at', CASE WHEN v_earned < 600 THEN 600 WHEN v_earned < 1000 THEN 1000 WHEN v_earned < 1300 THEN 1300 ELSE NULL END);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.minigame_weary_state(UUID) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Daily login bonus
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.daily_bonus_reward(p_cycle_day INTEGER)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'gold', CASE p_cycle_day WHEN 1 THEN 25 WHEN 2 THEN 35 WHEN 3 THEN 45 WHEN 4 THEN 55 WHEN 5 THEN 65 WHEN 6 THEN 75 ELSE 100 END,
    'food', CASE WHEN p_cycle_day = 7 THEN 10 ELSE 0 END,
    'wood', CASE WHEN p_cycle_day = 7 THEN 20 ELSE 0 END);
$$;

-- What today's claim would be: continues the streak after a 1-day gap, or a 2-day gap once per 7 days
CREATE OR REPLACE FUNCTION public.daily_bonus_next(p_user_id UUID, OUT claimed_today BOOLEAN, OUT streak INTEGER,
                                                  OUT cycle_day INTEGER, OUT grace BOOLEAN)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'America/Denver')::DATE;
  v_last RECORD;
  v_gap INTEGER;
BEGIN
  SELECT dl.day, dl.streak INTO v_last FROM daily_login_claims dl WHERE dl.user_id = p_user_id ORDER BY dl.day DESC LIMIT 1;
  claimed_today := v_last.day = v_today;
  grace := false;
  IF v_last.day IS NULL THEN
    streak := 1;
  ELSIF claimed_today THEN
    streak := v_last.streak;
  ELSE
    v_gap := v_today - v_last.day;
    IF v_gap = 1 THEN
      streak := v_last.streak + 1;
    ELSIF v_gap = 2 AND NOT EXISTS (SELECT 1 FROM daily_login_claims dl WHERE dl.user_id = p_user_id
                                    AND dl.grace_used AND dl.day > v_today - 7) THEN
      streak := v_last.streak + 1; grace := true;
    ELSE
      streak := 1;
    END IF;
  END IF;
  claimed_today := COALESCE(claimed_today, false);
  cycle_day := ((streak - 1) % 7) + 1;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.daily_bonus_next(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.daily_bonus_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  n RECORD;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  SELECT * INTO n FROM daily_bonus_next(v_user_id);
  RETURN jsonb_build_object('claimed_today', n.claimed_today, 'streak', n.streak, 'cycle_day', n.cycle_day,
                            'grace', n.grace, 'reward', daily_bonus_reward(n.cycle_day),
                            'weary', minigame_weary_state(v_user_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_today DATE := (now() AT TIME ZONE 'America/Denver')::DATE;
  n RECORD;
  v_reward JSONB;
  v_gold INTEGER; v_food INTEGER; v_wood INTEGER;
  v_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_authenticated'); END IF;
  PERFORM 1 FROM profiles WHERE id = v_user_id FOR UPDATE; -- one claim at a time per player
  SELECT * INTO n FROM daily_bonus_next(v_user_id);
  IF n.claimed_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_claimed', 'streak', n.streak);
  END IF;

  v_reward := daily_bonus_reward(n.cycle_day);
  v_gold := (v_reward->>'gold')::INT; v_food := (v_reward->>'food')::INT; v_wood := (v_reward->>'wood')::INT;
  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;
  IF v_status = 'BANNED' THEN v_gold := 0; v_food := 0; v_wood := 0; END IF;

  INSERT INTO daily_login_claims (user_id, day, streak, cycle_day, grace_used, gold, food, wood)
  VALUES (v_user_id, v_today, n.streak, n.cycle_day, n.grace, v_gold, v_food, v_wood);

  UPDATE profiles SET
    gold = COALESCE(gold, 0) + v_gold, gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold,
    food = COALESCE(food, 0) + v_food, food_earned_total = COALESCE(food_earned_total, 0) + v_food,
    wood = COALESCE(wood, 0) + v_wood, wood_earned_total = COALESCE(wood_earned_total, 0) + v_wood
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true, 'streak', n.streak, 'cycle_day', n.cycle_day, 'grace', n.grace,
    'gold', v_gold, 'food', v_food, 'wood', v_wood,
    'totals', (SELECT jsonb_build_object('gold', gold, 'food', food, 'wood', wood) FROM profiles WHERE id = v_user_id));
END;
$$;

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
    SELECT jsonb_agg(to_jsonb(t) ORDER BY t.current_streak DESC, t.last_claim DESC) FROM (
      SELECT pr.id AS user_id, pr.character_name,
             (SELECT n.streak FROM daily_bonus_next(pr.id) n WHERE NOT (n.streak = 1 AND NOT n.claimed_today)) AS current_streak,
             MAX(dl.day) AS last_claim,
             COUNT(*) FILTER (WHERE dl.day > (now() AT TIME ZONE 'America/Denver')::DATE - 30) AS claims_30d,
             COALESCE(SUM(dl.gold), 0) AS bonus_gold_total
      FROM profiles pr JOIN daily_login_claims dl ON dl.user_id = pr.id
      GROUP BY pr.id, pr.character_name) t
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.daily_bonus_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_daily_bonus() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_login_streaks() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.daily_bonus_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_login_streaks() TO authenticated;

-- ============================================================================
-- Mini-game rewards with the Weary taper (same as 20261011000500 otherwise)
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
  v_event_type := CASE WHEN v_rand < 0.25 THEN 'fishing' WHEN v_rand < 0.5 THEN 'blacksmith'
                       WHEN v_rand < 0.75 THEN 'murloc' ELSE NULL END;

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
  v_mult NUMERIC;
  -- fishing
  v_pos FLOAT; v_angle FLOAT; v_zone_start FLOAT; v_zone_end FLOAT;
  -- blacksmith
  v_hits INT := 0; v_attempts INT := 0; v_last_cycle INT := -1; v_cycle INT; v_phase FLOAT; i INT;
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
    -- Weary: payouts taper the more mini-game gold you've earned today
    v_mult := minigame_gold_multiplier(v_earned.gold);
    v_gold := round(v_gold * v_mult)::INT;
    v_capped := v_mult < 1;
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
    'success', v_won, 'won', v_won, 'capped', v_capped, 'weary', minigame_weary_state(v_user_id),
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
-- Gold Ledger: also counts the daily login bonus (same as 20261011000700 otherwise)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_gold_ledger(p_user_id uuid DEFAULT NULL, p_days integer DEFAULT 30, p_limit integer DEFAULT 1500)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := NOW() - make_interval(days => LEAST(GREATEST(p_days, 1), 365));
  v_result JSONB;
BEGIN
  IF NOT COALESCE((SELECT pr.protected FROM profiles pr WHERE pr.id = auth.uid()), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  WITH ledger AS (
    -- Mini-games and plain sparkles (gold + food)
    SELECT ge.created_at AT TIME ZONE 'UTC' AS at, ge.user_id, 'gold'::TEXT AS currency, ge.gold_awarded::BIGINT AS amount,
           'earned'::TEXT AS kind, CASE WHEN ge.game_type = 'normal_claim' THEN 'Sparkle' ELSE 'Mini-game: ' || ge.game_type END AS description,
           ge.flags AS flags
    FROM game_events ge WHERE ge.gold_awarded > 0
    UNION ALL
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'food', ge.food_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.food_awarded > 0
    UNION ALL
    -- Older games, rolled up into one row per player / day / game (see rollup_old_game_events)
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'gold', d.gold, 'earned',
           CASE WHEN d.game_type = 'normal_claim' THEN 'Sparkles' ELSE 'Mini-game: ' || d.game_type END || format(' (%s that day)', d.games),
           ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.gold > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'food', d.food, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.food > 0
    UNION ALL
    -- Daily login bonus (gold, food, wood)
    SELECT dl.claimed_at, dl.user_id, 'gold', dl.gold, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.gold > 0
    UNION ALL
    SELECT dl.claimed_at, dl.user_id, 'food', dl.food, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.food > 0
    UNION ALL
    SELECT dl.claimed_at, dl.user_id, 'wood', dl.wood, 'earned', format('Daily login bonus (day %s)', dl.cycle_day), ARRAY[]::TEXT[]
    FROM daily_login_claims dl WHERE dl.wood > 0
    UNION ALL
    -- Shop, stickers, ranks, admin changes, refunds
    SELECT gt.created_at, gt.user_id, 'gold',
           CASE WHEN gt.transaction_type = 'spent' THEN -ABS(gt.amount) ELSE gt.amount END,
           gt.transaction_type, COALESCE(gt.reason, gt.source, ''), ARRAY[]::TEXT[]
    FROM gold_transactions gt
    UNION ALL
    -- Pets, homes, Auction House, Shadowy Dealer (gold) and house tiers (wood)
    SELECT pl.purchased_at, pl.user_id,
           CASE WHEN pl.purchase_type = 'house_tier' THEN 'wood' ELSE 'gold' END,
           -ABS(COALESCE(pl.amount, 0))::BIGINT, 'spent', COALESCE(pl.description, pl.purchase_type), ARRAY[]::TEXT[]
    FROM purchase_log pl
    UNION ALL
    -- What Auction House bundles gave back (food / wood)
    SELECT pl.purchased_at, pl.user_id, pl.metadata->>'resource', (pl.metadata->>'amount')::BIGINT, 'earned',
           COALESCE(pl.description, 'Auction House'), ARRAY[]::TEXT[]
    FROM purchase_log pl WHERE pl.purchase_type IN ('food_bundle', 'wood_bundle') AND pl.metadata ? 'amount'
  ),
  windowed AS (
    SELECT l.* FROM ledger l
    WHERE l.at >= v_since AND (p_user_id IS NULL OR l.user_id = p_user_id)
  ),
  totals AS (
    -- All-time gold history per player, to check against their balance
    SELECT l.user_id, SUM(l.amount) FILTER (WHERE l.currency = 'gold') AS gold_net_all_time
    FROM ledger l GROUP BY l.user_id
  )
  SELECT jsonb_build_object(
    'since', v_since,
    'entries', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.at DESC) FROM (
        SELECT w.at, w.user_id, pr.character_name, w.currency, w.amount, w.kind, w.description, w.flags
        FROM windowed w LEFT JOIN profiles pr ON pr.id = w.user_id
        ORDER BY w.at DESC LIMIT LEAST(GREATEST(p_limit, 1), 5000)) e
    ), '[]'::jsonb),
    'players', COALESCE((
      SELECT jsonb_agg(to_jsonb(s) ORDER BY s.gold_earned DESC) FROM (
        SELECT pr.id AS user_id, pr.character_name, pr.gold AS current_gold, pr.food AS current_food, pr.wood AS current_wood,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'gold' AND w.amount > 0), 0) AS gold_earned,
               COALESCE(-SUM(w.amount) FILTER (WHERE w.currency = 'gold' AND w.amount < 0), 0) AS gold_spent,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'food'), 0) AS food_net,
               COALESCE(SUM(w.amount) FILTER (WHERE w.currency = 'wood'), 0) AS wood_net,
               COUNT(w.*) AS entries,
               -- Gold the history doesn't explain (positive = more than earned; e.g. old direct DB edits)
               pr.gold - COALESCE(t.gold_net_all_time, 0) AS gold_unexplained
        FROM profiles pr
        LEFT JOIN windowed w ON w.user_id = pr.id
        LEFT JOIN totals t ON t.user_id = pr.id
        WHERE p_user_id IS NULL OR pr.id = p_user_id
        GROUP BY pr.id, pr.character_name, pr.gold, pr.food, pr.wood, t.gold_net_all_time
        HAVING COUNT(w.*) > 0 OR pr.gold <> 0) s
    ), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) TO authenticated;
