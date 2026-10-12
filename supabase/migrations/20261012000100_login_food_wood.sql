-- Migration: weekly login - day 3 gives 10 food, day 5 gives 10 wood
-- Purpose: extra resources mid-week; day 7 unchanged (100 gold, 10 food, 20 wood, 5 crystals).
-- Date: 2026-10-12
-- Reverse: re-run daily_bonus_reward from 20261011001600.

CREATE OR REPLACE FUNCTION public.daily_bonus_reward(p_cycle_day INTEGER)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'gold', CASE p_cycle_day WHEN 1 THEN 25 WHEN 2 THEN 35 WHEN 3 THEN 45 WHEN 4 THEN 55 WHEN 5 THEN 65 WHEN 6 THEN 75 ELSE 100 END,
    'food', CASE p_cycle_day WHEN 3 THEN 10 WHEN 7 THEN 10 ELSE 0 END,
    'wood', CASE p_cycle_day WHEN 5 THEN 10 WHEN 7 THEN 20 ELSE 0 END,
    'crystals', CASE WHEN p_cycle_day = 7 THEN 5 ELSE 0 END);
$$;
