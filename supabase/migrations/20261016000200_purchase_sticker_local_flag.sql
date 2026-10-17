-- Migration: purchase_sticker - purchase flag for this transaction only
-- Purpose: purchase_sticker turned on app.allow_purchase with set_config(..., false), which lasts for the whole
--          database connection. Connections are pooled and reused by other members, so after a sticker purchase
--          the next member on that connection could update their own profile with protect_role_column's checks
--          skipped (gold, role, protected). Now set_config(..., true): the flag ends with the purchase's
--          transaction, like every other purchase function. Nothing else changes - the gold deduction, the ledger
--          row and the sticker are all in that same transaction.
-- Date: 2026-10-16
-- Reverse: re-run this function with the third set_config argument back to false (not recommended).

CREATE OR REPLACE FUNCTION public.purchase_sticker("p_gallery_image_id" "uuid", "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_current_gold BIGINT;
  v_new_gold BIGINT;
  v_sticker_price BIGINT;
  v_image_url TEXT;
  v_placed_by_name TEXT;
  v_pos_x DECIMAL(5,2);
  v_pos_y DECIMAL(5,2);
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  SELECT COALESCE(gi.sticker_price, gs.sticker_price) INTO v_sticker_price
  FROM public.gallery_images gi, public.guild_settings gs
  WHERE gi.id = p_gallery_image_id AND gs.id = 1;
  
  v_sticker_price := COALESCE(v_sticker_price, 10);

  SELECT gold INTO v_current_gold FROM public.profiles WHERE id = v_user_id;
  IF v_current_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'insufficient_gold');
  END IF;

  IF v_current_gold < v_sticker_price THEN
    RETURN jsonb_build_object('success', false, 'reason', 'insufficient_gold');
  END IF;

  SELECT url INTO v_image_url FROM public.gallery_images WHERE id = p_gallery_image_id;
  IF v_image_url IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_available');
  END IF;

  SELECT character_name INTO v_placed_by_name FROM public.profiles WHERE id = v_user_id;
  v_placed_by_name := COALESCE(v_placed_by_name, 'Anonymous');

  v_new_gold := v_current_gold - v_sticker_price;
  
  PERFORM set_config('app.allow_purchase', 'true', true);   -- this transaction only (was the whole pooled connection)
  
  UPDATE public.profiles
  SET gold = v_new_gold
  WHERE id = v_user_id;

  INSERT INTO public.gold_transactions (user_id, transaction_type, amount, reason, source)
  VALUES (v_user_id, 'spent', v_sticker_price, 'Sticker purchase', 'sticker');

  v_pos_x := (RANDOM() * 60 + 20)::DECIMAL(5,2);
  v_pos_y := (RANDOM() * 60 + 20)::DECIMAL(5,2);

  INSERT INTO public.stickers(
    gallery_image_id,
    image_url,
    placed_by_user_id,
    placed_by_name,
    placed_at,
    note,
    expires_at,
    position_x,
    position_y
  ) VALUES (
    p_gallery_image_id,
    v_image_url,
    v_user_id,
    v_placed_by_name,
    now(),
    p_note,
    now() + interval '14 days',
    v_pos_x,
    v_pos_y
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_gold', v_new_gold
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_sticker(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_sticker(uuid, text) TO authenticated;
