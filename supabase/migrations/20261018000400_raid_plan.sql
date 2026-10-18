-- Migration: raid plan (Boss Strategies)
-- Purpose: the Boss Strategies page's raid setup and per-boss assignments, which the Hated Companion addon will show
--          in game.
--   * raid_plan: one shared document (id = 1): tonight's roster (the raid roster plus any PUGs), the tanks, and each
--     healer's default tank. JSON so the page can grow without migrations.
--   * bosses.plan: per-fight assignments - tank jobs, healer overrides (only the ones that differ from the defaults),
--     interrupt / crowd-control jobs and kill order.
--   Every signed-in member can read both; Officers and the Raid Leader edit them.
-- Date: 2026-10-18
-- Reverse: DROP TABLE public.raid_plan; ALTER TABLE public.bosses DROP COLUMN plan;

CREATE TABLE IF NOT EXISTS public.raid_plan (
  id         int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  data       jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by uuid DEFAULT auth.uid(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.raid_plan (id, data) VALUES (1, '{}'::jsonb) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.raid_plan ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS raid_plan_read ON public.raid_plan;
CREATE POLICY raid_plan_read ON public.raid_plan FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS raid_plan_officer_write ON public.raid_plan;
CREATE POLICY raid_plan_officer_write ON public.raid_plan FOR ALL TO authenticated
  USING (public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected))
  WITH CHECK (public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
GRANT SELECT, INSERT, UPDATE ON public.raid_plan TO authenticated;
GRANT ALL ON public.raid_plan TO service_role;

ALTER TABLE public.bosses ADD COLUMN IF NOT EXISTS plan jsonb NOT NULL DEFAULT '{}'::jsonb;
