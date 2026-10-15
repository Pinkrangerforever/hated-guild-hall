-- Migration: let the war server write its tables
-- Purpose: staging's default privileges give even service_role only REFERENCES/TRIGGER/TRUNCATE/MAINTAIN on new
--   tables, so the `war` Edge Function (which runs as service_role) got "permission denied". Grant it what it uses:
--   the war tables, faction membership (for faction chat), and read access to pets (each player's site pet).
-- Date: 2026-10-15
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_war_games TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_war_log TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_war_medals TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.guild_war_medals_id_seq TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_war_config TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_war_members TO service_role;
GRANT SELECT ON public.pets TO service_role;
