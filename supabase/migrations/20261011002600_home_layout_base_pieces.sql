-- Migration: starting pieces are movable
-- Purpose: the props that come with a home zone (e.g. the lamp post and tree) can be moved and turned in
--          the decorate editor. save_home_layout now also keeps layout.base {"<index>": {x, z, r}},
--          validated like the houses (on the stage, numbers only). They can't be stored or removed.
-- Date: 2026-10-11
-- Reverse: re-run save_home_layout from 20261011002500.

CREATE OR REPLACE FUNCTION public.save_home_layout(p_home_id UUID, p_layout JSONB)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_home RECORD;
  v_houses JSONB := '{}'::jsonb;
  v_decor JSONB := '[]'::jsonb;
  v_base JSONB := '{}'::jsonb;
  v_key TEXT;
  v_val JSONB;
  v_x NUMERIC; v_z NUMERIC; v_r NUMERIC;
  v_zone TEXT;
  v_found BOOLEAN;
  v_used INTEGER;
  v_owned INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  SELECT h.id, h.zone, h.house_tier INTO v_home
  FROM public.player_homes h WHERE h.id = p_home_id AND h.user_id = v_user_id FOR UPDATE;
  IF v_home.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Home not found');
  END IF;
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Bad layout');
  END IF;

  -- houses: only tiers that are built, each once (object keys), on the stage
  IF jsonb_typeof(p_layout->'houses') = 'object' THEN
    FOR v_key, v_val IN SELECT * FROM jsonb_each(p_layout->'houses') LOOP
      IF v_key NOT IN ('1', '2', '3') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unknown house');
      END IF;
      IF v_key::INT > v_home.house_tier THEN
        RETURN jsonb_build_object('success', false, 'error', 'That house is not built yet');
      END IF;
      BEGIN
        v_x := round((v_val->>'x')::NUMERIC, 2); v_z := round((v_val->>'z')::NUMERIC, 2); v_r := round((v_val->>'r')::NUMERIC, 3);
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bad position');
      END;
      IF v_x IS NULL OR v_z IS NULL OR v_r IS NULL OR abs(v_x) > 6.5 OR abs(v_z) > 3.5 OR abs(v_r) > 7 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A house is off the stage');
      END IF;
      v_houses := v_houses || jsonb_build_object(v_key, jsonb_build_object('x', v_x, 'z', v_z, 'r', v_r));
    END LOOP;
  END IF;

  -- starting pieces that come with the zone: moved by index, on the stage
  IF jsonb_typeof(p_layout->'base') = 'object' THEN
    FOR v_key, v_val IN SELECT * FROM jsonb_each(p_layout->'base') LOOP
      IF v_key !~ '^[0-9]$' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unknown piece');
      END IF;
      BEGIN
        v_x := round((v_val->>'x')::NUMERIC, 2); v_z := round((v_val->>'z')::NUMERIC, 2); v_r := round((v_val->>'r')::NUMERIC, 3);
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bad position');
      END;
      IF v_x IS NULL OR v_z IS NULL OR v_r IS NULL OR abs(v_x) > 6.5 OR abs(v_z) > 3.5 OR abs(v_r) > 7 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A piece is off the stage');
      END IF;
      v_base := v_base || jsonb_build_object(v_key, jsonb_build_object('x', v_x, 'z', v_z, 'r', v_r));
    END LOOP;
  END IF;

  -- decor: known, allowed in this zone, on the stage, at most 40
  IF jsonb_typeof(p_layout->'decor') = 'array' THEN
    IF jsonb_array_length(p_layout->'decor') > 40 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Too many pieces (max 40)');
    END IF;
    FOR v_val IN SELECT * FROM jsonb_array_elements(p_layout->'decor') LOOP
      v_key := v_val->>'k';
      v_found := NULL;
      SELECT true, si.metadata->>'zone' INTO v_found, v_zone
      FROM public.shop_items si WHERE si.category = 'home_decor' AND si.metadata->>'key' = v_key LIMIT 1;
      IF v_found IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unknown piece');
      END IF;
      IF v_zone IS NOT NULL AND v_zone <> v_home.zone THEN
        RETURN jsonb_build_object('success', false, 'error', 'That piece belongs to another home');
      END IF;
      BEGIN
        v_x := round((v_val->>'x')::NUMERIC, 2); v_z := round((v_val->>'z')::NUMERIC, 2); v_r := round((v_val->>'r')::NUMERIC, 3);
      EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bad position');
      END;
      IF v_x IS NULL OR v_z IS NULL OR v_r IS NULL OR abs(v_x) > 6.5 OR abs(v_z) > 3.5 OR abs(v_r) > 7 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A piece is off the stage');
      END IF;
      v_decor := v_decor || jsonb_build_array(jsonb_build_object('k', v_key, 'x', v_x, 'z', v_z, 'r', v_r));
    END LOOP;
  END IF;

  -- ownership: pieces here + pieces already placed in the owner's other homes
  FOR v_key, v_used IN
    SELECT s.d->>'k', count(*)::INT FROM (
      SELECT jsonb_array_elements(v_decor) AS d
      UNION ALL
      SELECT jsonb_array_elements(COALESCE(h.layout->'decor', '[]'::jsonb))
      FROM public.player_homes h WHERE h.user_id = v_user_id AND h.id <> v_home.id
    ) s GROUP BY 1
  LOOP
    SELECT COALESCE((SELECT pd.qty FROM public.player_decor pd WHERE pd.user_id = v_user_id AND pd.item_key = v_key), 0) INTO v_owned;
    IF v_used > v_owned THEN
      RETURN jsonb_build_object('success', false, 'error', 'You placed more pieces than you own');
    END IF;
  END LOOP;

  UPDATE public.player_homes h SET layout = jsonb_build_object('houses', v_houses, 'decor', v_decor, 'base', v_base) WHERE h.id = v_home.id;
  RETURN jsonb_build_object('success', true, 'layout', jsonb_build_object('houses', v_houses, 'decor', v_decor, 'base', v_base));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_home_layout(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_home_layout(UUID, JSONB) TO authenticated;
