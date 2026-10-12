-- Migration: Miningjack + Goldjack earned decor
-- Purpose:
--   * Miningjack: granted at 150 Mining wins (uses the game-wins trigger from 20261011004300).
--   * Goldjack: granted at 50,000 lifetime gold earned. New stat-based rewards: metadata.reward_stat =
--     'gold_earned' + reward_goal, checked by a trigger on profiles.gold_earned_total.
--   * my_reward_progress() also reports gold_earned.
-- Date: 2026-10-11
-- Reverse: DROP TRIGGER trg_grant_stat_decor ON profiles; DROP FUNCTION grant_stat_decor();
--          re-run my_reward_progress from 20261011004300;
--          DELETE FROM shop_items WHERE metadata->>'key' IN ('miningjack', 'goldjack');

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT v.name, v.descr, 0, 'home_decor', v.meta, v.sort, true
FROM (VALUES
  ('Miningjack', 'A sturdy miner with his pick over his shoulder, always looking for the next vein. Earned by clearing the Mining mini-game 150 times.',
   '{"key":"miningjack","zone":null,"reward":"mining_wins","reward_game":"mining","reward_goal":150,"reward_text":"Clear the Mining mini-game 150 times"}'::jsonb, 202),
  ('Goldjack', 'A brawny porter hauling a sack of gold around your home. Earned by earning 50,000 gold in total.',
   '{"key":"goldjack","zone":null,"reward":"gold_earned","reward_stat":"gold_earned","reward_goal":50000,"reward_text":"Earn 50,000 gold in total"}'::jsonb, 203)
) AS v(name, descr, meta, sort)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items s WHERE s.category = 'home_decor' AND s.metadata->>'key' = v.meta->>'key');

CREATE OR REPLACE FUNCTION public.my_reward_progress()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_out JSONB := '{}'::jsonb;
  v_game TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RETURN v_out; END IF;
  FOR v_game IN SELECT DISTINCT si.metadata->>'reward_game' FROM shop_items si
                WHERE si.category = 'home_decor' AND si.metadata ? 'reward_game' LOOP
    v_out := v_out || jsonb_build_object(v_game, public.game_wins(auth.uid(), v_game));
  END LOOP;
  v_out := v_out || jsonb_build_object('gold_earned', (SELECT COALESCE(pr.gold_earned_total, 0) FROM profiles pr WHERE pr.id = auth.uid()));
  RETURN v_out;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.my_reward_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_reward_progress() TO authenticated;

CREATE OR REPLACE FUNCTION public.grant_stat_decor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
BEGIN
  FOR v_item IN SELECT si.metadata->>'key' AS k, (si.metadata->>'reward_goal')::INT AS goal FROM shop_items si
                WHERE si.category = 'home_decor' AND si.metadata->>'reward_stat' = 'gold_earned' LOOP
    IF COALESCE(NEW.gold_earned_total, 0) >= v_item.goal AND COALESCE(OLD.gold_earned_total, 0) < v_item.goal THEN
      INSERT INTO player_decor (user_id, item_key, qty) VALUES (NEW.id, v_item.k, 1)
      ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(player_decor.qty, 1);
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.grant_stat_decor() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_grant_stat_decor ON public.profiles;
CREATE TRIGGER trg_grant_stat_decor AFTER UPDATE OF gold_earned_total ON public.profiles
FOR EACH ROW WHEN (NEW.gold_earned_total IS DISTINCT FROM OLD.gold_earned_total) EXECUTE FUNCTION public.grant_stat_decor();

-- anyone already past a goal
INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, si.metadata->>'key', 1
FROM public.profiles p
JOIN public.shop_items si ON si.category = 'home_decor' AND si.metadata ? 'reward_game'
WHERE public.game_wins(p.id, si.metadata->>'reward_game') >= (si.metadata->>'reward_goal')::INT
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, si.metadata->>'key', 1
FROM public.profiles p
JOIN public.shop_items si ON si.category = 'home_decor' AND si.metadata->>'reward_stat' = 'gold_earned'
WHERE COALESCE(p.gold_earned_total, 0) >= (si.metadata->>'reward_goal')::INT
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
