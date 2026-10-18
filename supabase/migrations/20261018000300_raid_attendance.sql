-- Migration: raid attendance
-- Purpose: the Roster page's attendance table. One row per absence (raid night + member); no row = attended.
--          Every signed-in member can read it; Officers and the Raid Leader mark absences (including planned ones
--          on future nights). Raid nights are Sundays and Mondays from 2026-12-16 (worked out on the site).
-- Date: 2026-10-18
-- Reverse: DROP TABLE public.raid_attendance;

CREATE TABLE IF NOT EXISTS public.raid_attendance (
  raid_date  date NOT NULL,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  absent     boolean NOT NULL DEFAULT true,
  updated_by uuid DEFAULT auth.uid(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (raid_date, user_id)
);

ALTER TABLE public.raid_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS raid_attendance_read ON public.raid_attendance;
CREATE POLICY raid_attendance_read ON public.raid_attendance FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS raid_attendance_officer_write ON public.raid_attendance;
CREATE POLICY raid_attendance_officer_write ON public.raid_attendance FOR ALL TO authenticated
  USING (public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected))
  WITH CHECK (public.is_officer() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.raid_attendance TO authenticated;
GRANT ALL ON public.raid_attendance TO service_role;
