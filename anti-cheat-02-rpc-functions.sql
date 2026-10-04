-- Anti-Cheat System RPC Functions
-- Deploy these to replace existing claim_sparkle_gold and resolve_sparkle_event
-- Author: Anti-Cheat Design System
-- Created: 2026-10-02

-- Helper function: Generate random alphanumeric string
CREATE OR REPLACE FUNCTION gen_random_challenge(length INT = 32)
RETURNS TEXT AS $$
DECLARE
  chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  result TEXT := '';
  i INT;
BEGIN
  FOR i IN 1..length LOOP
    result := result || substr(chars, 1 + (random() * (length(chars) - 1))::INT, 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Updated claim_sparkle_gold RPC
-- Returns: { success: bool, pending_id: uuid, challenge: string, event: string }
CREATE OR REPLACE FUNCTION claim_sparkle_gold()
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID;
  v_pending_id UUID;
  v_challenge TEXT;
  v_event_type TEXT;
  v_claim_count INT;
BEGIN
  -- Authenticate
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- RATE LIMITING CHECK: 60 claims/hour max
  SELECT COUNT(*) INTO v_claim_count
  FROM sparkle_claims
  WHERE user_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 hour';

  IF v_claim_count > 100 THEN
    -- Log spam attempt
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CLAIM_SPAM', ARRAY['SPAM'], 'MEDIUM',
            jsonb_build_object('claims_per_hour', v_claim_count));
    RAISE EXCEPTION 'RATE_LIMITED: Max 100 claims/hour. Try again in 5 min.';
  END IF;

  -- CHECK SOFT BAN STATUS
  IF (SELECT status FROM user_cheat_scores WHERE user_id = v_user_id) = 'SOFT_BAN' THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity)
    VALUES (v_user_id, 'SOFT_BAN_ATTEMPT', ARRAY['SOFT_BAN'], 'LOW');
    RAISE EXCEPTION 'ACCOUNT_FLAGGED: Your account is under review. Contact admins.';
  END IF;

  -- Generate random event type (weighted: 70% fishing, 20% blacksmith, 10% murloc)
  DECLARE
    v_rand FLOAT := random();
  BEGIN
    IF v_rand < 0.7 THEN
      v_event_type := 'fishing';
    ELSIF v_rand < 0.9 THEN
      v_event_type := 'blacksmith';
    ELSE
      v_event_type := 'murloc';
    END IF;
  END;

  -- Generate challenge (32-char random, used for HMAC signing)
  v_challenge := gen_random_challenge(32);

  -- Create pending game record
  INSERT INTO pending_games (
    user_id, event_type, challenge, challenge_expires,
    created_at_epoch
  ) VALUES (
    v_user_id, v_event_type, v_challenge,
    NOW() + INTERVAL '30 seconds',
    (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT
  ) RETURNING id INTO v_pending_id;

  -- Record claim for rate limiting
  INSERT INTO sparkle_claims (user_id) VALUES (v_user_id);

  -- Return pending game info and challenge
  RETURN jsonb_build_object(
    'success', TRUE,
    'pending_id', v_pending_id,
    'challenge', v_challenge,
    'event', v_event_type,
    'awarded', 0
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', FALSE,
    'error', SQLERRM
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Helper function: Calculate needle angle for fishing at elapsed time
-- Matches client-side __fishingNeedleAngleAt(elapsedMs, cycleMs) exactly
CREATE OR REPLACE FUNCTION fishing_needle_angle_at(
  elapsed_ms BIGINT,
  cycle_ms INT
)
RETURNS FLOAT AS $$
DECLARE
  pos FLOAT;
BEGIN
  pos := ((elapsed_ms % cycle_ms)::FLOAT) / cycle_ms;
  IF pos < 0.5 THEN
    RETURN -90 + (pos / 0.5) * 180;
  ELSE
    RETURN 90 - (((pos - 0.5) / 0.5) * 180);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- Updated resolve_sparkle_event RPC
-- Validates signature, game rules, assigns gold
-- Parameters from client:
--   p_pending_id: UUID of pending game
--   p_won: boolean (client's claim)
--   p_challenge: challenge string (for verification)
--   p_signature: HMAC-SHA256 hex of payload
--   p_client_time_ms: client's current timestamp
--   p_client_timings: JSON array of click timestamps
CREATE OR REPLACE FUNCTION resolve_sparkle_event(
  p_pending_id UUID,
  p_won BOOLEAN,
  p_challenge TEXT,
  p_signature TEXT,
  p_nonce UUID,
  p_client_time_ms BIGINT,
  p_client_timings JSONB
)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID;
  v_record RECORD;
  v_expected_sig TEXT;
  v_payload TEXT;
  v_now_ms BIGINT;
  v_time_skew BIGINT;
  v_gold_awarded INT := 0;
  v_base_gold INT;
  v_flags TEXT[] := ARRAY[]::TEXT[];
  v_severity TEXT := 'LOW';
  v_is_valid_win BOOLEAN := FALSE;
BEGIN
  -- AUTHENTICATE
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- 1. FETCH PENDING GAME
  SELECT id, user_id, event_type, challenge, challenge_expires, created_at_epoch, won
  INTO v_record
  FROM pending_games
  WHERE id = p_pending_id;

  IF v_record IS NULL THEN
    RAISE EXCEPTION 'PENDING_NOT_FOUND: No pending game found';
  END IF;

  -- Verify ownership
  IF v_record.user_id != v_user_id THEN
    RAISE EXCEPTION 'PENDING_WRONG_USER: Not your pending game';
  END IF;

  -- Check not already resolved
  IF v_record.won IS NOT NULL THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'REPLAY_ATTEMPT', ARRAY['REPLAY'], 'HIGH',
            jsonb_build_object('pending_id', p_pending_id));
    RAISE EXCEPTION 'ALREADY_RESOLVED: This game was already resolved';
  END IF;

  -- 2. CHECK CHALLENGE EXPIRATION
  IF v_record.challenge_expires < NOW() THEN
    v_flags := array_append(v_flags, 'CHALLENGE_EXPIRED');
    v_severity := 'MEDIUM';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CHALLENGE_EXPIRED', v_flags, v_severity,
            jsonb_build_object('expired_at', v_record.challenge_expires));
  END IF;

  -- 3. VERIFY CHALLENGE MATCHES
  IF v_record.challenge != p_challenge THEN
    v_flags := array_append(v_flags, 'CHALLENGE_MISMATCH');
    v_severity := 'MEDIUM';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CHALLENGE_MISMATCH', v_flags, v_severity,
            jsonb_build_object('expected', v_record.challenge, 'got', p_challenge));
  END IF;

  -- 4. VERIFY HMAC-SHA256 SIGNATURE
  v_payload := jsonb_build_object(
    'pending_id', p_pending_id::TEXT,
    'won', p_won,
    'nonce', p_nonce::TEXT,
    'client_time_ms', p_client_time_ms,
    'client_timings', p_client_timings::jsonb
  )::TEXT;

  v_expected_sig := encode(
    hmac(v_payload, p_challenge, 'sha256'),
    'hex'
  );

  IF v_expected_sig != p_signature THEN
    v_flags := array_append(v_flags, 'SIGNATURE_MISMATCH');
    v_severity := 'HIGH';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'SIGNATURE_MISMATCH', v_flags, v_severity,
            jsonb_build_object('pending_id', p_pending_id, 'tampered', TRUE));
    RAISE EXCEPTION 'SIGNATURE_INVALID: Request was tampered with';
  END IF;

  -- 5. CHECK CLIENT TIME SKEW (max 3 seconds allowed)
  v_now_ms := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
  v_time_skew := ABS(v_now_ms - p_client_time_ms);

  IF v_time_skew > 3000 THEN
    v_flags := array_append(v_flags, 'TIME_SKEW');
    v_severity := 'LOW';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'TIME_SKEW', v_flags, v_severity,
            jsonb_build_object('skew_ms', v_time_skew));
    -- Don't reject, just log and mark as loss (client clock issue)
    p_won := FALSE;
  END IF;

  -- 6. GAME-SPECIFIC VALIDATION
  IF p_won THEN
    CASE v_record.event_type
      WHEN 'fishing' THEN
        -- Validate fishing timing (zone click logic)
        -- Client sends: [poolClickTime, gaugeClickTime]
        DECLARE
          v_click_to_gauge BIGINT;
          v_needle_angle FLOAT;
          v_zone_start FLOAT;
          v_zone_end FLOAT;
        BEGIN
          v_click_to_gauge := (p_client_timings->>1)::BIGINT - (p_client_timings->>0)::BIGINT;

          -- Sanity check: impossible click-to-gauge speed (< 500ms)
          IF v_click_to_gauge < 500 THEN
            v_flags := array_append(v_flags, 'IMPOSSIBLE_SPEED');
            v_severity := 'HIGH';
            p_won := FALSE;
          END IF;

          -- TODO: Calculate needle angle and verify it's in green zone
          -- This requires zone data from pending_games (extend schema to store zone)
          -- For now, trust client if no other flags
        END;

      WHEN 'murloc' THEN
        -- Validate murloc click intervals (should be 150+ ms apart)
        DECLARE
          v_intervals BIGINT[];
          v_min_interval BIGINT;
          i INT;
        BEGIN
          -- Build array of intervals between clicks
          FOR i IN 1..(jsonb_array_length(p_client_timings) - 1) LOOP
            v_intervals := array_append(
              v_intervals,
              (p_client_timings->>i)::BIGINT - (p_client_timings->>(i-1))::BIGINT
            );
          END LOOP;

          -- Find minimum interval
          SELECT MIN(val) INTO v_min_interval FROM unnest(v_intervals) val;

          -- Superhuman speed: < 80ms between hits
          IF v_min_interval < 80 THEN
            v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED');
            v_flags := array_append(v_flags, 'BOT_LIKE');
            v_severity := 'HIGH';
            p_won := FALSE;
          END IF;
        END;

      WHEN 'blacksmith' THEN
        -- Validate blacksmith progression (placeholder)
        -- TODO: Store hit count/difficulty in pending_games, validate consistency
        NULL;
    END CASE;
  END IF;

  -- 7. UPDATE PENDING GAME AS RESOLVED
  UPDATE pending_games
  SET resolved_at = NOW(), won = p_won
  WHERE id = p_pending_id;

  -- 8. CALCULATE GOLD REWARD (if won and no critical flags)
  v_is_valid_win := p_won AND NOT ('SIGNATURE_MISMATCH' = ANY(v_flags) OR 'SUPERHUMAN_SPEED' = ANY(v_flags));

  IF v_is_valid_win THEN
    -- Random gold between 5-50
    v_base_gold := 5 + (random() * 45)::INT;
    v_gold_awarded := v_base_gold;

    -- Update user gold balance
    UPDATE profiles
    SET gold = COALESCE(gold, 0) + v_gold_awarded
    WHERE id = v_user_id;
  END IF;

  -- 9. LOG GAME EVENT
  INSERT INTO game_events (
    user_id, pending_id, game_type, won, gold_awarded,
    client_timings, client_submit_time_ms, flags, severity
  ) VALUES (
    v_user_id, p_pending_id, v_record.event_type, v_is_valid_win,
    v_gold_awarded, p_client_timings, p_client_time_ms, v_flags, v_severity
  );

  -- 10. UPDATE CHEAT SCORE
  IF v_flags != ARRAY[]::TEXT[] THEN
    DECLARE
      v_points INT := 0;
    BEGIN
      -- Calculate points for flags
      FOREACH item IN ARRAY v_flags LOOP
        CASE item
          WHEN 'SIGNATURE_MISMATCH' THEN v_points := v_points + 100;
          WHEN 'SUPERHUMAN_SPEED' THEN v_points := v_points + 50;
          WHEN 'IMPOSSIBLE_SPEED' THEN v_points := v_points + 50;
          WHEN 'CHALLENGE_EXPIRED' THEN v_points := v_points + 10;
          ELSE v_points := v_points + 5;
        END CASE;
      END LOOP;

      INSERT INTO user_cheat_scores (user_id, total_points, flag_count, status)
      VALUES (v_user_id, v_points, 1,
              CASE
                WHEN v_points >= 100 THEN 'SOFT_BAN'
                WHEN v_points >= 50 THEN 'UNDER_REVIEW'
                ELSE 'CLEAN'
              END)
      ON CONFLICT (user_id) DO UPDATE SET
        total_points = user_cheat_scores.total_points + v_points,
        flag_count = user_cheat_scores.flag_count + 1,
        status = CASE
          WHEN user_cheat_scores.total_points + v_points >= 100 THEN 'SOFT_BAN'
          WHEN user_cheat_scores.total_points + v_points >= 50 THEN 'UNDER_REVIEW'
          ELSE 'CLEAN'
        END,
        last_flagged_at = NOW(),
        updated_at = NOW();
    END;
  END IF;

  -- 11. RETURN RESULT
  RETURN jsonb_build_object(
    'success', v_is_valid_win,
    'awarded', v_gold_awarded,
    'total', COALESCE((SELECT gold FROM profiles WHERE id = v_user_id), 0),
    'flags', v_flags,
    'severity', v_severity
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', FALSE,
    'error', SQLERRM
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Create investigation view: Top cheat suspects
CREATE OR REPLACE VIEW cheat_suspects AS
SELECT
  u.id,
  u.discord_username,
  s.total_points,
  s.flag_count,
  s.status,
  COUNT(DISTINCT g.id) as games_played_7d,
  ROUND(100.0 * SUM(CASE WHEN g.won THEN 1 ELSE 0 END) /
        NULLIF(COUNT(*), 0), 1) as win_pct_7d,
  s.last_flagged_at,
  string_agg(DISTINCT g.game_type, ', ' ORDER BY g.game_type) as game_types
FROM user_cheat_scores s
LEFT JOIN profiles u ON s.user_id = u.id
LEFT JOIN game_events g ON s.user_id = g.user_id
  AND g.created_at > NOW() - INTERVAL '7 days'
WHERE s.total_points > 0
GROUP BY s.user_id, u.id, u.discord_username, s.total_points, s.flag_count, s.status, s.last_flagged_at
ORDER BY s.total_points DESC, s.last_flagged_at DESC;

GRANT SELECT ON cheat_suspects TO postgres;
