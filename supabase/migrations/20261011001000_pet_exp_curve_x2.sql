-- Migration: Pet EXP curve doubled (same shape, twice the total)
-- Purpose: every level needs 2x the EXP: Level 10 (boss) 3675 -> 7350. Keep in sync with
--          EXP_REQUIREMENTS in index.html. Existing pets get their level recalculated from their EXP;
--          their stage (juvenile/adult/boss) is never lowered.
-- Date: 2026-10-11
-- Reverse: re-run pet_level_for_exp from 20261010000200 and recalculate levels the same way.

CREATE OR REPLACE FUNCTION public.pet_level_for_exp(p_exp INTEGER)
RETURNS INTEGER AS $$
  SELECT CASE
    WHEN COALESCE(p_exp, 0) >= 9550 THEN 11
    WHEN p_exp >= 7350 THEN 10
    WHEN p_exp >= 5600 THEN 9
    WHEN p_exp >= 4200 THEN 8
    WHEN p_exp >= 3050 THEN 7
    WHEN p_exp >= 2150 THEN 6
    WHEN p_exp >= 1450 THEN 5
    WHEN p_exp >= 900  THEN 4
    WHEN p_exp >= 500  THEN 3
    WHEN p_exp >= 200  THEN 2
    ELSE 1
  END;
$$ LANGUAGE sql IMMUTABLE;

UPDATE public.pets
SET level = public.pet_level_for_exp(exp), updated_at = now()
WHERE status <> 'egg' AND level IS DISTINCT FROM public.pet_level_for_exp(exp);

-- Feeding / petting recompute the stage from the level; never let that lower a pet's stage
CREATE OR REPLACE FUNCTION public.pets_keep_stage()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  rank_old INT := CASE old.status WHEN 'juvenile' THEN 1 WHEN 'adult' THEN 2 WHEN 'boss' THEN 3 ELSE 0 END;
  rank_new INT := CASE new.status WHEN 'juvenile' THEN 1 WHEN 'adult' THEN 2 WHEN 'boss' THEN 3 ELSE 0 END;
BEGIN
  IF rank_old > 0 AND rank_new < rank_old THEN
    new.status := old.status;
  END IF;
  RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS pets_keep_stage_trigger ON public.pets;
CREATE TRIGGER pets_keep_stage_trigger BEFORE UPDATE OF status ON public.pets
  FOR EACH ROW EXECUTE FUNCTION public.pets_keep_stage();
