-- Migration: Mining mini-game (shell game with copper nodes) + Crystals resource
-- Purpose:
--   * profiles.crystals (+ earned/spent totals): a rare 4th resource. Players can't edit it directly.
--   * mining: a gem shows in one of 3 copper nodes, then 7 swaps at a fixed speed (same for everyone);
--     pick the node with the gem. Server picks start + swaps, replays them, checks the pick and that the
--     shuffle actually had time to play. Pays 20-30 gold (Weary) + 1 crystal (15%: 2), max 5 crystals/day.
--   * game_events / game_events_daily get crystals columns; ledger + rollup include them.
--   * Odds: rare 5%, fishing/blacksmith/murloc 14%, trivia 12%, lumberjack 11%, mining 11%, plain gold 19%.
-- Date: 2026-10-11
-- Reverse: re-run claim/resolve/rollup/ledger from 20261011001300 and protect_role_column from
--          20261011000800_four_ranks; drop the crystal columns.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS crystals INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS crystals_earned_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS crystals_spent_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.game_events ADD COLUMN IF NOT EXISTS crystals_awarded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.game_events_daily ADD COLUMN IF NOT EXISTS crystals INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.pending_games DROP CONSTRAINT IF EXISTS pending_games_event_type_check;
ALTER TABLE public.pending_games ADD CONSTRAINT pending_games_event_type_check
  CHECK (event_type = ANY (ARRAY['fishing', 'blacksmith', 'murloc', 'trivia', 'lumberjack', 'rarespawn', 'mining']));
ALTER TABLE public.game_events DROP CONSTRAINT IF EXISTS game_events_game_type_check;
ALTER TABLE public.game_events ADD CONSTRAINT game_events_game_type_check
  CHECK (game_type = ANY (ARRAY['fishing', 'blacksmith', 'murloc', 'trivia', 'lumberjack', 'rarespawn', 'mining', 'normal_claim']));

CREATE OR REPLACE FUNCTION public.protect_role_column()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
begin
  -- Our own server functions (SECURITY DEFINER, owned by postgres), migrations and the SQL editor
  -- are trusted. Only direct API requests from players are checked below.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if old.protected = true then
    if new.role is distinct from old.role or new.protected is distinct from old.protected then
      raise exception 'This account is protected and can only be changed by the Discord sync process';
    end if;
  end if;

  -- Ranks change only through set_member_rank (which enforces who may promote whom)
  if new.role is distinct from old.role then
    raise exception 'Ranks can only be changed with set_member_rank';
  end if;

  if new.protected is distinct from old.protected then
    raise exception 'Protected status can only be changed by the Discord sync process';
  end if;

  if new.gold is distinct from old.gold or new.last_gold_claim_at is distinct from old.last_gold_claim_at then
    if not (public.is_officer() or (select p.discord_rank_level from public.profiles p where p.id = auth.uid()) = 1) then
      raise exception 'Gold can only be changed by the sparkle claim process or by Raid Leaders';
    end if;
  end if;

  if new.food is distinct from old.food
     or new.wood is distinct from old.wood
     or new.food_earned_total is distinct from old.food_earned_total
     or new.food_spent_total is distinct from old.food_spent_total
     or new.wood_earned_total is distinct from old.wood_earned_total
     or new.crystals is distinct from old.crystals
     or new.crystals_earned_total is distinct from old.crystals_earned_total
     or new.crystals_spent_total is distinct from old.crystals_spent_total
     or new.wood_spent_total is distinct from old.wood_spent_total
     or new.gold_earned_total is distinct from old.gold_earned_total
     or new.gold_spent_total is distinct from old.gold_spent_total
     or new.discord_rank_level is distinct from old.discord_rank_level then
    raise exception 'Resources, totals and rank can only be changed by the game itself';
  end if;

  return new;
end;
$$;

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
  -- rare 5%, fishing/blacksmith/murloc 14% each, trivia 12%, lumberjack 11%, mining 11%, plain gold 19%
  v_event_type := CASE WHEN v_rand < 0.05 THEN 'rarespawn' WHEN v_rand < 0.19 THEN 'fishing'
                       WHEN v_rand < 0.33 THEN 'blacksmith' WHEN v_rand < 0.47 THEN 'murloc'
                       WHEN v_rand < 0.59 THEN 'trivia' WHEN v_rand < 0.70 THEN 'lumberjack'
                       WHEN v_rand < 0.81 THEN 'mining' ELSE NULL END;

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
  v_wood INT := 0;
  v_crystals INT := 0;
  v_crystals_today INT;
  c_crystal_cap CONSTANT INT := 5;
  v_slot INT;
  v_sw JSONB;
  v_wood_today INT;
  c_wood_cap CONSTANT INT := 100;
  v_tri FLOAT; v_last_t INT := -100000; v_win INT; v_last_win INT := -1; v_dist FLOAT;
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

  SELECT * INTO v_rec FROM pending_games WHERE id = p_pending_id FOR UPDATE; -- includes secret
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

  ELSIF v_rec.event_type = 'lumberjack' AND v_n >= 1 THEN
    -- timings: ms of each chop. The axe marker sweeps 0 -> 1 -> 0 along the log every sweep_ms;
    -- a chop counts if the marker is over the current notch (the notch moves after every good chop).
    v_reaction := v_t[1];
    FOR i IN 1..v_n LOOP
      EXIT WHEN v_attempts >= (v_p->>'max_attempts')::INT OR v_hits >= (v_p->>'hits_needed')::INT;
      EXIT WHEN v_t[i] > (v_p->>'game_ms')::INT;
      IF v_t[i] - v_last_t < 250 THEN CONTINUE; END IF; -- the axe needs a moment between swings
      v_last_t := v_t[i];
      v_attempts := v_attempts + 1;
      v_tri := (v_t[i] % (v_p->>'sweep_ms')::INT)::FLOAT / (v_p->>'sweep_ms')::FLOAT;
      v_pos := CASE WHEN v_tri < 0.5 THEN v_tri * 2 ELSE 2 - v_tri * 2 END;
      IF abs(v_pos - (v_p->'notches'->>v_hits)::FLOAT) <= (v_p->>'width')::FLOAT / 2 THEN v_hits := v_hits + 1; END IF;
    END LOOP;
    v_won := v_hits >= (v_p->>'hits_needed')::INT;
    IF v_t[v_n] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'rarespawn' AND v_n >= 3 THEN
    -- timings: [ms, x, y] per click (x/y in thousandths of the arena). The elite jumps every jump_ms;
    -- one hit per jump, only on its weak spot, and not in the first 150 ms after it lands somewhere new.
    v_reaction := v_t[1];
    FOR i IN 0..(v_n / 3) - 1 LOOP
      EXIT WHEN v_t[i * 3 + 1] > (v_p->>'duration_ms')::INT;
      v_win := v_t[i * 3 + 1] / (v_p->>'jump_ms')::INT;
      CONTINUE WHEN v_win = v_last_win OR v_win >= jsonb_array_length(v_p->'positions');
      CONTINUE WHEN v_t[i * 3 + 1] - v_win * (v_p->>'jump_ms')::INT < 150;
      v_dist := sqrt(power(v_t[i * 3 + 2] - (v_p->'positions'->v_win->>0)::INT, 2) + power(v_t[i * 3 + 3] - (v_p->'positions'->v_win->>1)::INT, 2));
      IF v_dist <= (v_p->>'radius')::INT THEN v_hits := v_hits + 1; v_last_win := v_win; END IF;
    END LOOP;
    v_won := v_hits >= (v_p->>'hits_needed')::INT;
    IF v_t[v_n - 2] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'mining' AND v_n >= 2 THEN
    -- timings: [ms from the end of the shuffle to the pick, picked slot 0-2]. Follow the gem through the swaps.
    v_reaction := v_t[1];
    v_slot := (v_p->>'gem_start')::INT;
    FOR v_sw IN SELECT * FROM jsonb_array_elements(v_p->'swaps') LOOP
      IF v_slot = (v_sw->>0)::INT THEN v_slot := (v_sw->>1)::INT;
      ELSIF v_slot = (v_sw->>1)::INT THEN v_slot := (v_sw->>0)::INT; END IF;
    END LOOP;
    v_won := v_t[2] = v_slot AND v_t[1] <= (v_p->>'pick_ms')::INT + 500;
    -- The reveal + shuffle takes a fixed time; a pick before that could only come from a script
    IF v_server_elapsed + 1500 < (v_p->>'reveal_ms')::INT + jsonb_array_length(v_p->'swaps') * (v_p->>'swap_ms')::INT THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'trivia' AND v_n >= 2 THEN
    -- timings: [ms until the answer was clicked, chosen option 0-3]
    v_reaction := v_t[1];
    v_won := v_t[2] = (v_rec.secret->>'correct')::INT AND v_t[1] <= (v_p->>'time_ms')::INT + 500;
    IF v_t[1] < 900 THEN -- nobody reads a question and four answers in under a second
      v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; v_won := false;
    END IF;
    IF v_t[1] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;
  END IF;

  -- (blacksmith's first swing can legitimately land in the opening window, so it isn't checked)
  IF v_rec.event_type NOT IN ('blacksmith', 'trivia', 'rarespawn') AND v_reaction IS NOT NULL AND v_reaction < c_min_reaction THEN
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
      WHEN 'trivia' THEN 20 + (random() * 15)::INT
      WHEN 'lumberjack' THEN 5 + (random() * 5)::INT
      WHEN 'rarespawn' THEN 90 + (random() * 40)::INT
      WHEN 'mining' THEN 20 + (random() * 10)::INT
      ELSE 20 + (random() * 10)::INT END;
    v_food := CASE WHEN v_rec.event_type IN ('murloc', 'fishing') THEN 2 + floor(random() * 3)::INT
                   WHEN v_rec.event_type = 'rarespawn' THEN 5 ELSE 0 END;
    v_wood := CASE WHEN v_rec.event_type = 'lumberjack' THEN 4 + floor(random() * 5)::INT
                   WHEN v_rec.event_type = 'rarespawn' THEN 10 ELSE 0 END;
    -- Wood from mini-games is capped at 100 a day
    SELECT COALESCE(SUM(ge.wood_awarded), 0) INTO v_wood_today FROM game_events ge
    WHERE ge.user_id = v_user_id
      AND ge.created_at >= (date_trunc('day', now() AT TIME ZONE 'America/Denver') AT TIME ZONE 'America/Denver') AT TIME ZONE 'UTC';
    IF v_wood_today + v_wood > c_wood_cap THEN v_wood := GREATEST(c_wood_cap - v_wood_today, 0); v_capped := true; END IF;
    -- Crystals: the rare resource. 1 per mining win (15% chance of 2), max 5 a day
    v_crystals := CASE WHEN v_rec.event_type = 'mining' THEN CASE WHEN random() < 0.15 THEN 2 ELSE 1 END ELSE 0 END;
    SELECT COALESCE(SUM(ge.crystals_awarded), 0) INTO v_crystals_today FROM game_events ge
    WHERE ge.user_id = v_user_id
      AND ge.created_at >= (date_trunc('day', now() AT TIME ZONE 'America/Denver') AT TIME ZONE 'America/Denver') AT TIME ZONE 'UTC';
    IF v_crystals_today + v_crystals > c_crystal_cap THEN v_crystals := GREATEST(c_crystal_cap - v_crystals_today, 0); v_capped := true; END IF;
    -- Weary: payouts taper the more mini-game gold you've earned today
    v_mult := minigame_gold_multiplier(v_earned.gold);
    v_gold := round(v_gold * v_mult)::INT;
    v_capped := v_mult < 1;
    IF v_earned.food + v_food > c_food_cap THEN v_food := GREATEST(c_food_cap - v_earned.food, 0); v_capped := true; END IF;
    IF v_gold > 0 OR v_food > 0 OR v_wood > 0 OR v_crystals > 0 THEN
      UPDATE profiles
      SET gold = COALESCE(gold, 0) + v_gold, gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold,
          food = COALESCE(food, 0) + v_food, food_earned_total = COALESCE(food_earned_total, 0) + v_food,
          wood = COALESCE(wood, 0) + v_wood, wood_earned_total = COALESCE(wood_earned_total, 0) + v_wood,
          crystals = COALESCE(crystals, 0) + v_crystals, crystals_earned_total = COALESCE(crystals_earned_total, 0) + v_crystals
      WHERE id = v_user_id;
    END IF;
  END IF;

  INSERT INTO game_events (user_id, pending_id, game_type, won, gold_awarded, food_awarded, wood_awarded, crystals_awarded, client_timings,
                           client_submit_time_ms, flags, severity, reaction_ms, client_claimed_win, cheat_score_delta)
  VALUES (v_user_id, p_pending_id, v_rec.event_type, v_won, v_gold, v_food, v_wood, v_crystals, p_client_timings, p_client_time_ms,
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
    'answer', CASE WHEN v_rec.event_type = 'trivia' THEN (v_rec.secret->>'correct')::INT END, -- revealed only after the game is decided
    'awarded', v_gold, 'food_awarded', v_food, 'wood_awarded', v_wood, 'crystals_awarded', v_crystals,
    'crystals_total', (SELECT crystals FROM profiles WHERE id = v_user_id),
    'gem_slot', CASE WHEN v_rec.event_type = 'mining' THEN v_slot END,
    'wood_total', (SELECT wood FROM profiles WHERE id = v_user_id),
    'total', (SELECT gold FROM profiles WHERE id = v_user_id),
    'food_total', (SELECT food FROM profiles WHERE id = v_user_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.rollup_old_game_events(p_keep_days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMP := (NOW() AT TIME ZONE 'UTC') - make_interval(days => GREATEST(p_keep_days, 7));
  v_moved INTEGER;
BEGIN
  WITH old AS (
    DELETE FROM game_events ge WHERE ge.created_at < v_cutoff RETURNING ge.*
  ), agg AS (
    SELECT o.user_id, (o.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Denver')::DATE AS day, o.game_type,
           COUNT(*)::INT AS games, COUNT(*) FILTER (WHERE o.won)::INT AS wins,
           COALESCE(SUM(o.gold_awarded), 0)::INT AS gold, COALESCE(SUM(o.food_awarded), 0)::INT AS food, COALESCE(SUM(o.wood_awarded), 0)::INT AS wood, COALESCE(SUM(o.crystals_awarded), 0)::INT AS crystals,
           COUNT(*) FILTER (WHERE o.flags <> ARRAY[]::TEXT[])::INT AS flagged, MIN(o.reaction_ms) AS fastest
    FROM old o GROUP BY 1, 2, 3
  ), ins AS (
    INSERT INTO game_events_daily AS d (user_id, day, game_type, games, wins, gold, food, wood, crystals, flagged, fastest_reaction_ms)
    SELECT * FROM agg
    ON CONFLICT (user_id, day, game_type) DO UPDATE SET
      games = d.games + EXCLUDED.games, wins = d.wins + EXCLUDED.wins, gold = d.gold + EXCLUDED.gold,
      food = d.food + EXCLUDED.food, wood = d.wood + EXCLUDED.wood, crystals = d.crystals + EXCLUDED.crystals, flagged = d.flagged + EXCLUDED.flagged,
      fastest_reaction_ms = LEAST(d.fastest_reaction_ms, EXCLUDED.fastest_reaction_ms)
    RETURNING 1
  )
  SELECT COALESCE((SELECT SUM(games) FROM agg), 0) INTO v_moved FROM (SELECT COUNT(*) FROM ins) x;
  RETURN v_moved;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.rollup_old_game_events(INTEGER) FROM PUBLIC, anon, authenticated;

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
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'wood', ge.wood_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.wood_awarded > 0
    UNION ALL
    SELECT ge.created_at AT TIME ZONE 'UTC', ge.user_id, 'crystals', ge.crystals_awarded, 'earned', 'Mini-game: ' || ge.game_type, ge.flags
    FROM game_events ge WHERE ge.crystals_awarded > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'crystals', d.crystals, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.crystals > 0
    UNION ALL
    SELECT (d.day::timestamp AT TIME ZONE 'America/Denver'), d.user_id, 'wood', d.wood, 'earned',
           'Mini-game: ' || d.game_type || format(' (%s that day)', d.games), ARRAY[]::TEXT[]
    FROM game_events_daily d WHERE d.wood > 0
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

REVOKE EXECUTE ON FUNCTION public.claim_sparkle_gold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_sparkle_gold() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_gold_ledger(uuid, integer, integer) TO authenticated;
