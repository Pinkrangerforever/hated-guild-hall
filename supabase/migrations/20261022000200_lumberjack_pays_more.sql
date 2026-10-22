-- Migration: Lumberjack pays 20-25 gold
-- Purpose: a lumberjack win paid only 5-10 gold (plus its 4-8 wood), far below every other mini-game. Now 20-25 gold.
--          Only that one payout changes; resolve_sparkle_event is otherwise identical to 20261017000300.
-- Date: 2026-10-22
-- Reverse: re-run resolve_sparkle_event from 20261017000300_fishing_swims_from_start.sql

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
  -- fishing simulation (DOUBLE PRECISION throughout so it matches the browser exactly)
  f_seed BIGINT; f_u DOUBLE PRECISION; f_v DOUBLE PRECISION;
  f_fpos DOUBLE PRECISION; f_fv DOUBLE PRECISION; f_target DOUBLE PRECISION;
  f_bpos DOUBLE PRECISION; f_bv DOUBLE PRECISION; f_barh DOUBLE PRECISION; f_prog DOUBLE PRECISION;
  f_chance DOUBLE PRECISION; f_maxv DOUBLE PRECISION; f_a1 DOUBLE PRECISION; f_t1 DOUBLE PRECISION; f_a2 DOUBLE PRECISION; f_t2 DOUBLE PRECISION; f_w1 DOUBLE PRECISION; f_w2 DOUBLE PRECISION; f_w3 DOUBLE PRECISION; f_p2 DOUBLE PRECISION; f_range DOUBLE PRECISION; f_bias DOUBLE PRECISION; f_pull DOUBLE PRECISION; f_damp DOUBLE PRECISION;
  f_hold BOOLEAN := false; v_secret_note TEXT; f_tick INT; f_ti INT := 1; f_end INT := -1; f_perfect BOOLEAN := true;
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
  -- campfire
  c_i INT; c_n INT; c_k INT; c_t INT; c_slot INT; c_cyc INT; c_lastcyc INT := -1; c_tries INT := 0; c_hit INT := -1;
  c_g DOUBLE PRECISION := 0.15; c_inzone INT := 0; c_hold BOOLEAN := false; c_bend INT := -1; c_tick INT; c_tidx INT; c_tn INT;
  c_size INT := 1; c_heat DOUBLE PRECISION := 1; c_last INT := 0; c_fend INT := -1; c_used INT[] := ARRAY[]::INT[];
  c_kind TEXT; c_psize INT; c_perfect BOOLEAN := true; c_rounds JSONB; c_round INT := 0;
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

  IF v_rec.event_type = 'fishing' THEN
    -- timings: the ticks (60 per second, counted from the hook) at which the button was pressed or
    -- released, alternating, starting released. Replay the catch with the same seed and physics.
    IF v_n > 600 THEN v_n := 600; END IF;
    f_seed := (v_p->>'seed')::BIGINT;
    f_barh := (v_p->>'bar_h')::DOUBLE PRECISION;
    -- the fish swims from the first tick (FISH_BEHAVIOR / makeFishSim in index.html): a slow sweep, a quicker
    -- smaller one and a little bobble, speeds and phases drawn from the seed; sinker/floater drift down/up
    f_a1   := CASE v_p->>'behavior' WHEN 'dart' THEN 0.26 WHEN 'smooth' THEN 0.26 WHEN 'sinker' THEN 0.26 WHEN 'floater' THEN 0.26 ELSE 0.28 END;
    f_t1   := CASE v_p->>'behavior' WHEN 'dart' THEN 5 WHEN 'smooth' THEN 6.5 ELSE 5.5 END;
    f_a2   := CASE v_p->>'behavior' WHEN 'dart' THEN 0.08 WHEN 'smooth' THEN 0.05 ELSE 0.07 END;
    f_t2   := CASE v_p->>'behavior' WHEN 'dart' THEN 2.6 WHEN 'smooth' THEN 3.6 ELSE 3.2 END;
    f_bias := CASE v_p->>'behavior' WHEN 'sinker' THEN -0.12 WHEN 'floater' THEN 0.12 ELSE 0 END;
    f_seed := (f_seed * 48271) % 2147483647; f_u := f_seed::DOUBLE PRECISION / 2147483647::DOUBLE PRECISION;
    f_seed := (f_seed * 48271) % 2147483647; f_v := f_seed::DOUBLE PRECISION / 2147483647::DOUBLE PRECISION;
    f_w1 := 2 * pi() / (60 * f_t1 * (0.85 + f_u * 0.3)) * CASE WHEN f_v < 0.5 THEN -1 ELSE 1 END;
    f_seed := (f_seed * 48271) % 2147483647; f_u := f_seed::DOUBLE PRECISION / 2147483647::DOUBLE PRECISION;
    f_seed := (f_seed * 48271) % 2147483647; f_v := f_seed::DOUBLE PRECISION / 2147483647::DOUBLE PRECISION;
    f_w2 := 2 * pi() / (60 * f_t2 * (0.85 + f_u * 0.3)); f_p2 := f_v * 2 * pi();
    f_w3 := 2 * pi() / 36;
    f_fpos := 0.5; f_fv := 0; f_target := 0.5; f_bpos := 0.5 - f_barh / 2; f_bv := 0; f_prog := 0.3; -- bar starts around the fish
    FOR f_tick IN 0..((v_p->>'max_ticks')::INT - 1) LOOP
      WHILE f_ti <= v_n AND v_t[f_ti] <= f_tick LOOP f_hold := NOT f_hold; f_ti := f_ti + 1; END LOOP;
      -- fish
      f_fpos := 0.5 + f_bias * LEAST(1, f_tick::DOUBLE PRECISION / 240) + f_a1 * sin(f_w1 * f_tick)
                + f_a2 * (sin(f_w2 * f_tick + f_p2) - sin(f_p2)) + 0.008 * sin(f_w3 * f_tick);
      IF f_fpos < 0.03 THEN f_fpos := 0.03; END IF;
      IF f_fpos > 0.97 THEN f_fpos := 0.97; END IF;
      f_fpos := floor(f_fpos * 1000000 + 0.5) / 1000000;
      -- bar
      f_bv := f_bv + CASE WHEN f_hold THEN 0.00075 ELSE -0.0007 END;
      f_bv := f_bv * 0.935;
      IF f_bv > 0.008 THEN f_bv := 0.008; END IF;
      IF f_bv < -0.008 THEN f_bv := -0.008; END IF;
      f_bpos := f_bpos + f_bv;
      IF f_bpos < 0 THEN f_bpos := 0; f_bv := -f_bv * 0.35; END IF;
      IF f_bpos > 1 - f_barh THEN f_bpos := 1 - f_barh; f_bv := -f_bv * 0.35; END IF;
      -- catch meter
      IF f_fpos >= f_bpos AND f_fpos <= f_bpos + f_barh THEN f_prog := f_prog + 0.0032;
      ELSE f_prog := f_prog - 0.0035; f_perfect := false; END IF;
      IF f_prog >= 1 THEN v_won := true; f_end := f_tick; EXIT; END IF;
      IF f_prog <= 0 THEN f_end := f_tick; EXIT; END IF;
    END LOOP;
    -- The catch takes real time: it can't be submitted faster than it could be played
    IF f_end >= 0 AND v_server_elapsed + 2000 < (f_end * 1000) / 60 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;
    IF v_won AND f_perfect THEN v_secret_note := 'perfect'; END IF;

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

  ELSIF v_rec.event_type = 'campfire' AND v_n >= 1 THEN
    -- timings: [n, strike ms..., n, blow toggle ticks..., n, (feed ms, tray slot)...], each stage timed from its start
    c_rounds := v_p->'rounds';
    -- 1) strike: one counted strike per sweep, strike_tries tries, a hit in the hot zone lights a spark
    c_n := LEAST(GREATEST(COALESCE(v_t[1], 0), 0), 50); c_i := 2;
    FOR c_k IN 1..c_n LOOP
      c_t := v_t[c_i + c_k - 1];
      EXIT WHEN c_t IS NULL OR c_tries >= (v_p->>'strike_tries')::INT OR c_t > (v_p->>'strike_ms')::INT * (v_p->>'strike_tries')::INT;
      c_cyc := c_t / (v_p->>'strike_ms')::INT;
      CONTINUE WHEN c_cyc = c_lastcyc;
      c_lastcyc := c_cyc; c_tries := c_tries + 1;
      -- the hot zone is at the END of each sweep (the right side of the bar)
      IF (c_t % (v_p->>'strike_ms')::INT)::DOUBLE PRECISION / (v_p->>'strike_ms')::DOUBLE PRECISION >= 1 - (v_p->>'strike_win')::DOUBLE PRECISION THEN
        c_hit := c_t; EXIT;
      END IF;
      c_perfect := false;
    END LOOP;
    c_i := c_i + c_n;
    -- 2) blow: 60 ticks a second, glow rises while held and sinks when not; too high scatters the ember
    c_tn := LEAST(GREATEST(COALESCE(v_t[c_i], 0), 0), 400); c_tidx := c_i + 1;
    IF c_hit >= 0 THEN
      FOR c_tick IN 0..((v_p->>'blow_ticks')::INT - 1) LOOP
        WHILE c_tidx <= c_i + c_tn AND v_t[c_tidx] IS NOT NULL AND v_t[c_tidx] <= c_tick LOOP c_hold := NOT c_hold; c_tidx := c_tidx + 1; END LOOP;
        c_g := c_g + CASE WHEN c_hold THEN (v_p->>'blow_up')::DOUBLE PRECISION ELSE -(v_p->>'blow_down')::DOUBLE PRECISION END;
        IF c_g < 0 THEN c_g := 0; END IF;
        EXIT WHEN c_g >= 0.97;
        IF c_g >= (v_p->>'blow_lo')::DOUBLE PRECISION AND c_g <= (v_p->>'blow_hi')::DOUBLE PRECISION THEN c_inzone := c_inzone + 1; END IF;
        IF c_inzone >= (v_p->>'blow_need')::INT THEN c_bend := c_tick; EXIT; END IF;
      END LOOP;
    END IF;
    c_i := c_i + 1 + c_tn;
    -- 3) feed: four rounds of three pieces; the right one grows the fire and refills its heat, a wrong one costs heat
    --    (the fire never shrinks); the heat fades all the while
    IF c_bend >= 0 THEN
      c_n := LEAST(GREATEST(COALESCE(v_t[c_i], 0), 0), 20); c_i := c_i + 1;
      FOR c_k IN 0..(c_n - 1) LOOP
        c_t := v_t[c_i + c_k * 2]; c_slot := v_t[c_i + c_k * 2 + 1];
        EXIT WHEN c_t IS NULL OR c_slot IS NULL;
        CONTINUE WHEN c_t < c_last OR c_slot < 0 OR c_slot > 2 OR (c_round * 3 + c_slot) = ANY(c_used);
        c_heat := c_heat - ((v_p->>'feed_decay')::DOUBLE PRECISION * (c_t - c_last)::DOUBLE PRECISION) / 1000.0; c_last := c_t;
        EXIT WHEN c_heat <= 0;
        c_used := array_append(c_used, c_round * 3 + c_slot);
        c_kind := c_rounds->c_round->>c_slot;
        c_psize := CASE c_kind WHEN 'tinder' THEN 1 WHEN 'kindling' THEN 2 WHEN 'sticks' THEN 3 WHEN 'log' THEN 4 ELSE 9 END;
        IF c_psize = c_size THEN c_size := c_size + 1; c_heat := 1; c_round := c_round + 1;
        ELSE
          c_perfect := false;
          c_heat := c_heat - CASE WHEN c_kind = 'wet' THEN 0.35 WHEN c_kind = 'leaves' THEN 0.25 WHEN c_kind = 'stone' THEN 0.15
                                  WHEN c_psize > c_size THEN 0.3 ELSE 0.15 END;
        END IF;
        EXIT WHEN c_heat <= 0;
        IF c_size >= 5 THEN v_won := true; c_fend := c_t; EXIT; END IF;
      END LOOP;
    END IF;
    -- the whole fire takes real time to light
    IF v_won AND v_server_elapsed + 3000 < c_hit + (c_bend * 1000) / 60 + c_fend THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;
    IF v_won AND c_perfect THEN v_secret_note := 'perfect'; END IF;

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
  IF v_rec.event_type NOT IN ('blacksmith', 'trivia', 'rarespawn', 'fishing', 'campfire') AND v_reaction IS NOT NULL AND v_reaction < c_min_reaction THEN
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
      WHEN 'fishing' THEN 25 + (random() * 10)::INT + CASE WHEN v_secret_note = 'perfect' THEN 10 ELSE 0 END
      WHEN 'murloc' THEN 15 + (random() * 10)::INT
      WHEN 'trivia' THEN 20 + (random() * 15)::INT
      WHEN 'lumberjack' THEN 20 + (random() * 5)::INT   -- was 5-10 (2026-10-22): lumberjack pays like the other games
      WHEN 'rarespawn' THEN 90 + (random() * 40)::INT
      WHEN 'mining' THEN 20 + (random() * 10)::INT
      WHEN 'campfire' THEN 20 + (random() * 10)::INT + CASE WHEN v_secret_note = 'perfect' THEN 10 ELSE 0 END
      ELSE 20 + (random() * 10)::INT END;
    v_food := CASE WHEN v_rec.event_type IN ('murloc', 'fishing', 'campfire') THEN 2 + floor(random() * 3)::INT
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
    'perfect', v_secret_note = 'perfect',
    'wood_total', (SELECT wood FROM profiles WHERE id = v_user_id),
    'total', (SELECT gold FROM profiles WHERE id = v_user_id),
    'food_total', (SELECT food FROM profiles WHERE id = v_user_id));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) TO authenticated;
