-- Migration: Phase 2 pet cleanup
-- Purpose:
--   * Allow up to 3 pets per player (was 1 via UNIQUE(user_id)); cap enforced in purchase_pet_egg
--   * Server computes pet level + evolution stage from exp (L1-4 juvenile, L5-9 adult, L10+ boss)
--   * feed_pet / pet_action return level, status and whether the pet levelled up
--   * Murloc minigame wins also award 2-4 Food (resolve_sparkle_event, 8-arg version the client uses).
--     Gold logic in resolve_sparkle_event is copied unchanged from the live definition.
-- Date: 2026-10-10
-- Reverse: re-add UNIQUE(user_id) on pets (only if every user has <= 1 pet), drop the two helper
--          functions, and re-run 20261010000100 + the previous resolve_sparkle_event definition.

-- ============================================================================
-- 1. Up to 3 pets per player
-- ============================================================================
ALTER TABLE public.pets DROP CONSTRAINT IF EXISTS unique_active_pet_per_user;

-- ============================================================================
-- 2. Level / stage helpers (match EXP_REQUIREMENTS in index.html)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.pet_level_for_exp(p_exp INTEGER)
RETURNS INTEGER AS $$
  SELECT CASE
    WHEN COALESCE(p_exp, 0) >= 4775 THEN 11
    WHEN p_exp >= 3675 THEN 10
    WHEN p_exp >= 2800 THEN 9
    WHEN p_exp >= 2100 THEN 8
    WHEN p_exp >= 1525 THEN 7
    WHEN p_exp >= 1075 THEN 6
    WHEN p_exp >= 725  THEN 5
    WHEN p_exp >= 450  THEN 4
    WHEN p_exp >= 250  THEN 3
    WHEN p_exp >= 100  THEN 2
    ELSE 1
  END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.pet_stage_for_level(p_level INTEGER)
RETURNS TEXT AS $$
  SELECT CASE
    WHEN p_level >= 10 THEN 'boss'
    WHEN p_level >= 5  THEN 'adult'
    ELSE 'juvenile'
  END;
$$ LANGUAGE sql IMMUTABLE;

-- ============================================================================
-- 3. purchase_pet_egg: same as 20261010000100 plus the 3-pet cap
-- ============================================================================
CREATE OR REPLACE FUNCTION public.purchase_pet_egg(p_user_id UUID, p_pet_type TEXT, p_egg_cost INTEGER)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_max_pets INTEGER := 3;
  v_item RECORD;
  v_current_gold INTEGER;
  v_pet_count INTEGER;
  v_now_ms BIGINT;
  v_hatch_time_ms BIGINT;
  v_new_pet_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'No trader access');
  END IF;

  SELECT si.id, si.name, si.cost INTO v_item
  FROM public.shop_items si
  WHERE si.category = 'pet_egg'
    AND si.active = true
    AND si.metadata->>'pet_type' = p_pet_type
  ORDER BY si.sort_order
  LIMIT 1;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That egg is not for sale');
  END IF;

  -- Lock the profile row first so the pet-count check and gold spend can't race
  SELECT pr.gold INTO v_current_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;

  SELECT count(*) INTO v_pet_count FROM public.pets p WHERE p.user_id = v_user_id;
  IF v_pet_count >= v_max_pets THEN
    RETURN jsonb_build_object('success', false, 'error', format('You can own up to %s pets', v_max_pets));
  END IF;

  IF v_current_gold IS NULL OR v_current_gold < v_item.cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  PERFORM set_config('app.allow_purchase', 'true', true);
  UPDATE public.profiles pr
  SET gold = pr.gold - v_item.cost,
      gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
  WHERE pr.id = v_user_id;
  PERFORM set_config('app.allow_purchase', 'false', true);

  v_now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_hatch_time_ms := v_now_ms + 86400000;

  INSERT INTO public.pets (user_id, pet_type, status, hatch_time)
  VALUES (v_user_id, p_pet_type, 'egg', v_hatch_time_ms)
  RETURNING id INTO v_new_pet_id;

  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'shop_item', v_item.cost, v_item.name,
          jsonb_build_object('pet_type', p_pet_type, 'pet_id', v_new_pet_id));

  RETURN jsonb_build_object(
    'success', true,
    'pet_id', v_new_pet_id,
    'pet_type', p_pet_type,
    'status', 'egg',
    'hatch_time_ms', v_hatch_time_ms,
    'new_gold', v_current_gold - v_item.cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 4. feed_pet: 5 food -> +10 exp, now also updates level + stage
-- ============================================================================
CREATE OR REPLACE FUNCTION public.feed_pet(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_food_cost INTEGER := 5;
  v_exp_reward INTEGER := 10;
  v_pet RECORD;
  v_current_food INTEGER;
  v_new_exp INTEGER;
  v_new_level INTEGER;
  v_new_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT p.id, p.status, p.exp, p.level INTO v_pet
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  FOR UPDATE;
  IF v_pet.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_pet.status = 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Eggs can''t eat yet');
  END IF;

  SELECT COALESCE(pr.food, 0) INTO v_current_food FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_current_food < v_food_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient food');
  END IF;

  UPDATE public.profiles pr
  SET food = COALESCE(pr.food, 0) - v_food_cost,
      food_spent_total = COALESCE(pr.food_spent_total, 0) + v_food_cost
  WHERE pr.id = v_user_id;

  v_new_exp := COALESCE(v_pet.exp, 0) + v_exp_reward;
  v_new_level := public.pet_level_for_exp(v_new_exp);
  v_new_status := public.pet_stage_for_level(v_new_level);

  UPDATE public.pets p
  SET exp = v_new_exp, level = v_new_level, status = v_new_status, updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fed pet',
    'food_remaining', v_current_food - v_food_cost,
    'pet_exp', v_new_exp,
    'level', v_new_level,
    'status', v_new_status,
    'leveled_up', v_new_level > COALESCE(v_pet.level, 1)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 5. pet_action: +5 exp, 1hr cooldown, now also updates level + stage
-- ============================================================================
CREATE OR REPLACE FUNCTION public.pet_action(p_user_id UUID, p_pet_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_now_ms BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_cooldown_ms BIGINT := 3600000;
  v_exp_reward INTEGER := 5;
  v_pet RECORD;
  v_new_exp INTEGER;
  v_new_level INTEGER;
  v_new_status TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT p.id, p.status, p.exp, p.level, p.last_pet_action_time INTO v_pet
  FROM public.pets p
  WHERE p.id = p_pet_id AND p.user_id = v_user_id
  FOR UPDATE;
  IF v_pet.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet not found');
  END IF;
  IF v_pet.status = 'egg' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Eggs can''t be petted yet');
  END IF;
  IF v_pet.last_pet_action_time IS NOT NULL AND (v_now_ms - v_pet.last_pet_action_time) < v_cooldown_ms THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pet needs to rest (1hr cooldown)',
                              'last_pet_action_time', v_pet.last_pet_action_time);
  END IF;

  v_new_exp := COALESCE(v_pet.exp, 0) + v_exp_reward;
  v_new_level := public.pet_level_for_exp(v_new_exp);
  v_new_status := public.pet_stage_for_level(v_new_level);

  UPDATE public.pets p
  SET exp = v_new_exp, level = v_new_level, status = v_new_status,
      last_pet_action_time = v_now_ms, updated_at = now()
  WHERE p.id = p_pet_id AND p.user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Pet happily received attention',
    'pet_exp', v_new_exp,
    'level', v_new_level,
    'status', v_new_status,
    'leveled_up', v_new_level > COALESCE(v_pet.level, 1),
    'last_pet_action_time', v_now_ms
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 6. resolve_sparkle_event (8-arg, used by index.html): murloc win -> +2-4 food
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
