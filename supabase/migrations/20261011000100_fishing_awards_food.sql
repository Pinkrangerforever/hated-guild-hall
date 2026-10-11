-- Migration: Fishing wins also award food
-- Purpose: resolve_sparkle_event now gives 2-4 food on fishing wins too (murloc already did).
--          Same function as 20261010000200 otherwise.
-- Date: 2026-10-11
-- Reverse: re-run the resolve_sparkle_event block from 20261010000200_phase2_pet_cleanup.sql

--    Everything else is the live definition, unchanged.
-- ============================================================================
CREATE OR REPLACE FUNCTION "public"."resolve_sparkle_event"("p_pending_id" "uuid", "p_won" boolean, "p_challenge" "text", "p_signature" "text", "p_nonce" "uuid", "p_client_time_ms" bigint, "p_client_timings" "jsonb", "p_payload" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id UUID;
  v_record RECORD;
  v_expected_sig TEXT;
  v_gold_awarded INT := 0;
  v_food_awarded INT := 0;
  v_flags TEXT[] := ARRAY[]::TEXT[];
  v_severity TEXT := 'LOW';
  item TEXT;
  v_points INT := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- Allow sparkle claim process to update gold (bypass role check in trigger)
  PERFORM set_config('app.allow_sparkle_claim', 'true', false);

  SELECT id, user_id, event_type, challenge, challenge_expires, created_at_epoch, won
  INTO v_record
  FROM pending_games
  WHERE id = p_pending_id;

  IF v_record IS NULL THEN
    RAISE EXCEPTION 'PENDING_NOT_FOUND: No pending game found';
  END IF;

  IF v_record.user_id != v_user_id THEN
    RAISE EXCEPTION 'PENDING_WRONG_USER: Not your pending game';
  END IF;

  IF v_record.won IS NOT NULL THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'REPLAY_ATTEMPT', ARRAY['REPLAY'], 'HIGH',
            jsonb_build_object('pending_id', p_pending_id));
    RAISE EXCEPTION 'ALREADY_RESOLVED: This game was already resolved';
  END IF;

  IF v_record.challenge_expires < NOW() THEN
    v_flags := array_append(v_flags, 'CHALLENGE_EXPIRED');
    v_severity := 'MEDIUM';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CHALLENGE_EXPIRED', v_flags, v_severity,
            jsonb_build_object('expired_at', v_record.challenge_expires));
  END IF;

  IF v_record.challenge != p_challenge THEN
    v_flags := array_append(v_flags, 'CHALLENGE_MISMATCH');
    v_severity := 'MEDIUM';
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CHALLENGE_MISMATCH', v_flags, v_severity,
            jsonb_build_object('expected', v_record.challenge, 'got', p_challenge));
  END IF;

  -- Verify signature using exact payload string client sent
  v_expected_sig := encode(
    hmac(p_payload, p_challenge, 'sha256'),
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

  UPDATE pending_games SET won = p_won, resolved_at = NOW() WHERE id = p_pending_id;

  IF p_won AND v_severity != 'HIGH' THEN
    v_gold_awarded := CASE v_record.event_type
      WHEN 'fishing' THEN 10 + 15 + (random() * 10)::INT
      WHEN 'murloc' THEN 10 + 5 + (random() * 10)::INT
      WHEN 'blacksmith' THEN 10 + 10 + (random() * 10)::INT
      ELSE 8 + (random() * 7)::INT
    END;

    -- Food rewards (other minigames can be added here later)
    v_food_awarded := CASE v_record.event_type
      WHEN 'murloc' THEN 2 + floor(random() * 3)::INT   -- 2-4 food
      WHEN 'fishing' THEN 2 + floor(random() * 3)::INT  -- 2-4 food
      ELSE 0
    END;

    UPDATE profiles
    SET gold = COALESCE(gold, 0) + v_gold_awarded,
        gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold_awarded,
        food = COALESCE(food, 0) + v_food_awarded,
        food_earned_total = COALESCE(food_earned_total, 0) + v_food_awarded
    WHERE id = v_user_id;
  END IF;

  INSERT INTO game_events (user_id, pending_id, game_type, won, gold_awarded,
                          client_timings, client_submit_time_ms, flags, severity)
  VALUES (v_user_id, p_pending_id, v_record.event_type, p_won AND v_severity != 'HIGH',
          v_gold_awarded, p_client_timings, p_client_time_ms, v_flags, v_severity);

  IF v_flags != ARRAY[]::TEXT[] THEN
    v_points := 0;
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
  END IF;

  RETURN jsonb_build_object(
    'success', p_won AND v_severity != 'HIGH',
    'awarded', v_gold_awarded,
    'total', COALESCE((SELECT gold FROM profiles WHERE id = v_user_id), 0),
    'food_awarded', v_food_awarded,
    'food_total', COALESCE((SELECT food FROM profiles WHERE id = v_user_id), 0),
    'flags', v_flags,
    'severity', v_severity
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', FALSE,
    'error', SQLERRM
  );
END;
$$;
