-- Migration: Baby Murloc - earned decor
-- Purpose: decor can be an achievement reward (shop_items metadata.reward). The Baby Murloc (roaming NPC,
--          any home) is given automatically to every player who has won the Murloc mini-game 150 times
--          (game_events + the archived game_events_daily). It can't be bought.
--   * murloc_wins(user)          lifetime Murloc wins
--   * my_reward_progress()       the signed-in player's progress toward earned decor
--   * trigger on game_events     grants the Baby Murloc on the 150th win
--   * backfill for anyone already there
-- Date: 2026-10-11
-- Reverse: DROP TRIGGER trg_grant_baby_murloc ON game_events; DROP FUNCTION grant_baby_murloc(),
--          my_reward_progress(), murloc_wins(uuid); re-run purchase_decor from 20261011003400;
--          DELETE FROM shop_items WHERE metadata->>'key' = 'baby_murloc'; (player_decor rows stay)

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Baby Murloc', 'Mrglglgl! A tiny murloc that waddles around your home and dances. Earned by clearing the Murloc mini-game 150 times.',
       0, 'home_decor', '{"key":"baby_murloc","zone":null,"reward":"murloc_wins","reward_goal":150,"reward_text":"Clear the Murloc mini-game 150 times"}'::jsonb, 200, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'baby_murloc');

CREATE OR REPLACE FUNCTION public.murloc_wins(p_user UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (SELECT COUNT(*) FROM game_events ge WHERE ge.user_id = p_user AND ge.game_type = 'murloc' AND ge.won)::INT
       + COALESCE((SELECT SUM(d.wins) FROM game_events_daily d WHERE d.user_id = p_user AND d.game_type = 'murloc'), 0)::INT;
$$;
REVOKE EXECUTE ON FUNCTION public.murloc_wins(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.my_reward_progress()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN '{}'::jsonb; END IF;
  RETURN jsonb_build_object('murloc_wins', public.murloc_wins(auth.uid()));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.my_reward_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_reward_progress() TO authenticated;

CREATE OR REPLACE FUNCTION public.grant_baby_murloc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM player_decor pd WHERE pd.user_id = NEW.user_id AND pd.item_key = 'baby_murloc' AND pd.qty > 0)
     AND public.murloc_wins(NEW.user_id) >= 150 THEN
    INSERT INTO player_decor (user_id, item_key, qty) VALUES (NEW.user_id, 'baby_murloc', 1)
    ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(player_decor.qty, 1);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.grant_baby_murloc() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_grant_baby_murloc ON public.game_events;
CREATE TRIGGER trg_grant_baby_murloc AFTER INSERT ON public.game_events
FOR EACH ROW WHEN (NEW.game_type = 'murloc' AND NEW.won) EXECUTE FUNCTION public.grant_baby_murloc();

-- anyone already past 150
INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, 'baby_murloc', 1 FROM public.profiles p WHERE public.murloc_wins(p.id) >= 150
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);

CREATE OR REPLACE FUNCTION public.purchase_decor(p_item_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_item RECORD;
  v_gold INTEGER;
  v_key TEXT;
  v_qty INTEGER;
  v_crystals INTEGER;
  v_by_crystal BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  SELECT si.id, si.name, si.cost, si.metadata INTO v_item
  FROM public.shop_items si WHERE si.id = p_item_id AND si.category = 'home_decor' AND si.active = true;
  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That piece is not for sale');
  END IF;
  IF v_item.metadata ? 'reward' THEN
    RETURN jsonb_build_object('success', false, 'error', 'This piece can only be earned');
  END IF;
  v_key := v_item.metadata->>'key';
  v_by_crystal := COALESCE(v_item.metadata->>'currency', 'gold') = 'crystals';
  SELECT pr.gold, COALESCE(pr.crystals, 0) INTO v_gold, v_crystals FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_by_crystal THEN
    -- rare pieces: crystals only
    IF v_crystals < v_item.cost THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not enough crystals');
    END IF;
    UPDATE public.profiles pr SET crystals = COALESCE(pr.crystals, 0) - v_item.cost WHERE pr.id = v_user_id;
  ELSE
    IF v_gold IS NULL OR v_gold < v_item.cost THEN
      RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
    END IF;
    UPDATE public.profiles pr
    SET gold = pr.gold - v_item.cost, gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_item.cost
    WHERE pr.id = v_user_id;
  END IF;
  INSERT INTO public.player_decor (user_id, item_key, qty) VALUES (v_user_id, v_key, 1)
  ON CONFLICT (user_id, item_key) DO UPDATE SET qty = public.player_decor.qty + 1
  RETURNING qty INTO v_qty;
  INSERT INTO public.purchase_log (user_id, item_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, v_item.id, 'home_decor', v_item.cost, v_item.name, jsonb_build_object('key', v_key, 'currency', CASE WHEN v_by_crystal THEN 'crystals' ELSE 'gold' END));
  RETURN jsonb_build_object('success', true, 'key', v_key, 'qty', v_qty, 'item_name', v_item.name,
    'new_gold', CASE WHEN v_by_crystal THEN v_gold ELSE v_gold - v_item.cost END,
    'new_crystals', CASE WHEN v_by_crystal THEN v_crystals - v_item.cost ELSE v_crystals END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_decor(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_decor(UUID) TO authenticated;
