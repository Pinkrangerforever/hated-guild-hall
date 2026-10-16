-- Migration: re-match every pet's stage to its level
-- Purpose: when the EXP curve doubled (20261011001000) pets kept their old stage even though their level dropped,
--   so e.g. a level 7 dragon stayed a boss. The user chose to make stage follow level again, once, for everyone:
--   levels 1-4 juvenile, 5-9 adult, 10+ boss (eggs untouched). pets_keep_stage stays in place afterwards, so a
--   stage still never drops from here on.
-- Date: 2026-10-15
-- Reverse: not reversible automatically (the previous stages are in the nightly backups).

ALTER TABLE public.pets DISABLE TRIGGER pets_keep_stage_trigger;

UPDATE public.pets
SET status = CASE WHEN level >= 10 THEN 'boss' WHEN level >= 5 THEN 'adult' ELSE 'juvenile' END,
    updated_at = now()
WHERE status <> 'egg'
  AND status IS DISTINCT FROM (CASE WHEN level >= 10 THEN 'boss' WHEN level >= 5 THEN 'adult' ELSE 'juvenile' END);

ALTER TABLE public.pets ENABLE TRIGGER pets_keep_stage_trigger;
