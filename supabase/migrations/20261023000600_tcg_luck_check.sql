-- Migration: Hated TCG luck check on card drops
-- Purpose: every sync, tcg-sync adds up how many card drops an account's kills SHOULD have given (each kill's odds) and
--          how many it actually got. If the account is far luckier than the odds allow (about a 1 in 10,000 chance or
--          less), that sync's cards are held here for the Raid Leader instead of being added (its points still pay).
--   * tcg_accounts.drop_expected / drop_actual   the running totals
--   * tcg_held_drops                             held cards: approve adds them (tcg_add_drops), reject drops them
-- Date: 2026-10-23
-- Reverse: DROP TABLE public.tcg_held_drops; ALTER TABLE public.tcg_accounts DROP COLUMN drop_expected, DROP COLUMN drop_actual;

ALTER TABLE public.tcg_accounts ADD COLUMN IF NOT EXISTS drop_expected double precision NOT NULL DEFAULT 0;
ALTER TABLE public.tcg_accounts ADD COLUMN IF NOT EXISTS drop_actual int NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.tcg_held_drops (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  drops       jsonb NOT NULL,                    -- what tcg_add_drops would have been given
  expected    double precision NOT NULL,         -- the account's expected drops so far (including this sync)
  actual      int NOT NULL,                      -- and its actual drops
  chance      double precision NOT NULL,         -- how likely that much luck is
  status      text NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'approved', 'rejected')),
  at          timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz
);
ALTER TABLE public.tcg_held_drops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tcg_held_drops_read ON public.tcg_held_drops;
CREATE POLICY tcg_held_drops_read ON public.tcg_held_drops FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND protected));
GRANT SELECT ON public.tcg_held_drops TO authenticated;
GRANT ALL ON public.tcg_held_drops TO service_role;
