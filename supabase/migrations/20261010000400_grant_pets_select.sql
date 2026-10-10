-- Migration: Let signed-in players read pets
-- Purpose: The Phase 2 tables were created without table privileges for the API roles
--          (this project's default privileges grant no SELECT), so loadPets() always failed
--          and the pet widget vanished after a reload. RLS ("Public can view pets") still applies.
--          Also drop TRUNCATE, which the defaults handed to anon/authenticated on the new tables.
-- Date: 2026-10-10
-- Reverse: REVOKE SELECT ON public.pets FROM authenticated;

GRANT SELECT ON public.pets TO authenticated;

REVOKE TRUNCATE ON public.pets, public.house, public.house_additions,
                   public.mystery_trader_access, public.purchase_log
  FROM anon, authenticated;
