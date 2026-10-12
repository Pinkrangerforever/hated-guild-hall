-- Migration: earned decor for any mini-game + the Lumberjack
-- Purpose: earned decor is now data-driven: a home_decor item with metadata.reward_game (a game_type) and
--          metadata.reward_goal (wins) is granted automatically once a player's lifetime wins of that game
--          reach the goal. Replaces the Baby Murloc-only trigger. Adds the Lumberjack (150 lumberjack wins).
--   * game_wins(user, game)    lifetime wins (game_events + archived game_events_daily)
--   * my_reward_progress()     { <game_type>: wins } for every game that has an earned piece
--   * grant_earned_decor()     trigger on game_events (won rows)
-- Date: 2026-10-11
-- Reverse: DROP TRIGGER trg_grant_earned_decor ON game_events; DROP FUNCTION grant_earned_decor(), game_wins(uuid, text);
--          re-run 20261011004200 (Baby Murloc trigger + my_reward_progress);
--          DELETE FROM shop_items WHERE metadata->>'key' = 'lumberjack_npc';

UPDATE public.shop_items SET metadata = metadata || '{"reward_game":"murloc"}'::jsonb
WHERE category = 'home_decor' AND metadata->>'key' = 'baby_murloc';

INSERT INTO public.shop_items (name, description, cost, category, metadata, sort_order, active)
SELECT 'Lumberjack', 'A hard-working peasant hauling timber around your home. Earned by clearing the Lumberjack mini-game 150 times.',
       0, 'home_decor', '{"key":"lumberjack_npc","zone":null,"reward":"lumberjack_wins","reward_game":"lumberjack","reward_goal":150,"reward_text":"Clear the Lumberjack mini-game 150 times"}'::jsonb, 201, true
WHERE NOT EXISTS (SELECT 1 FROM public.shop_items WHERE category = 'home_decor' AND metadata->>'key' = 'lumberjack_npc');

CREATE OR REPLACE FUNCTION public.game_wins(p_user UUID, p_game TEXT)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (SELECT COUNT(*) FROM game_events ge WHERE ge.user_id = p_user AND ge.game_type = p_game AND ge.won)::INT
       + COALESCE((SELECT SUM(d.wins) FROM game_events_daily d WHERE d.user_id = p_user AND d.game_type = p_game), 0)::INT;
$$;
REVOKE EXECUTE ON FUNCTION public.game_wins(UUID, TEXT) FROM PUBLIC, anon, authenticated;

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
  RETURN v_out;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.my_reward_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_reward_progress() TO authenticated;

CREATE OR REPLACE FUNCTION public.grant_earned_decor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_wins INTEGER := NULL;
BEGIN
  FOR v_item IN SELECT si.metadata->>'key' AS k, (si.metadata->>'reward_goal')::INT AS goal FROM shop_items si
                WHERE si.category = 'home_decor' AND si.metadata->>'reward_game' = NEW.game_type LOOP
    IF NOT EXISTS (SELECT 1 FROM player_decor pd WHERE pd.user_id = NEW.user_id AND pd.item_key = v_item.k AND pd.qty > 0) THEN
      IF v_wins IS NULL THEN v_wins := public.game_wins(NEW.user_id, NEW.game_type); END IF;
      IF v_wins >= v_item.goal THEN
        INSERT INTO player_decor (user_id, item_key, qty) VALUES (NEW.user_id, v_item.k, 1)
        ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(player_decor.qty, 1);
      END IF;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.grant_earned_decor() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_grant_baby_murloc ON public.game_events;
DROP FUNCTION IF EXISTS public.grant_baby_murloc();
DROP FUNCTION IF EXISTS public.murloc_wins(UUID);
DROP TRIGGER IF EXISTS trg_grant_earned_decor ON public.game_events;
CREATE TRIGGER trg_grant_earned_decor AFTER INSERT ON public.game_events
FOR EACH ROW WHEN (NEW.won) EXECUTE FUNCTION public.grant_earned_decor();

-- anyone already past a goal
INSERT INTO public.player_decor (user_id, item_key, qty)
SELECT p.id, si.metadata->>'key', 1
FROM public.profiles p
JOIN public.shop_items si ON si.category = 'home_decor' AND si.metadata ? 'reward_game'
WHERE public.game_wins(p.id, si.metadata->>'reward_game') >= (si.metadata->>'reward_goal')::INT
ON CONFLICT (user_id, item_key) DO UPDATE SET qty = GREATEST(public.player_decor.qty, 1);
