-- Migration: Hated TCG spawn id checks
-- Purpose: kills now arrive with the creature's spawn id (addon 3.6, HTCG5). tcg-sync drops kills whose spawn id
--          doesn't add up, without holding anything for review:
--   * tcg_accounts.wow_server   the WoW server number an account's kills come from (set by its first spawn ids)
--   * tcg_npc_maps              which map each creature has been seen on, and by whom; once 2+ players have seen a
--                               creature on some maps, a kill of it on a different map is dropped
-- Date: 2026-10-22
-- Reverse: DROP TABLE public.tcg_npc_maps; ALTER TABLE public.tcg_accounts DROP COLUMN wow_server;

ALTER TABLE public.tcg_accounts ADD COLUMN IF NOT EXISTS wow_server int;

CREATE TABLE IF NOT EXISTS public.tcg_npc_maps (
  npc_id   int  NOT NULL,
  map_id   int  NOT NULL,
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  first_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (npc_id, map_id, user_id)
);
ALTER TABLE public.tcg_npc_maps ENABLE ROW LEVEL SECURITY;   -- no policies: only the server (service role) uses it
GRANT ALL ON public.tcg_npc_maps TO service_role;
