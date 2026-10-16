-- Migration: link in-game character names to website members
-- Purpose: guild bank donations arrive under WoW character names, which rarely match the site's names. The Raid
--   Leader links each character to a member here; the donation leaderboards then add a member's characters up under
--   their site name. Members can read the links; only the protected Raid Leader can change them (through the RPCs).
-- Date: 2026-10-15
-- Reverse: DROP FUNCTION link_character(text, uuid), unlink_character(text); DROP TABLE guild_character_links;

CREATE TABLE IF NOT EXISTS public.guild_character_links (
  character_name TEXT PRIMARY KEY CHECK (character_name = lower(character_name) AND char_length(character_name) BETWEEN 1 AND 48),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  linked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS guild_character_links_profile ON public.guild_character_links (profile_id);
ALTER TABLE public.guild_character_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members read character links" ON public.guild_character_links;
CREATE POLICY "Members read character links" ON public.guild_character_links FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.guild_character_links FROM anon, authenticated;
GRANT SELECT ON public.guild_character_links TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.guild_character_links TO service_role;

CREATE OR REPLACE FUNCTION public.link_character(p_character TEXT, p_profile UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_name TEXT := lower(btrim(coalesce(p_character, '')));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND protected) THEN RAISE EXCEPTION 'Raid Leader only'; END IF;
  IF v_name = '' THEN RAISE EXCEPTION 'No character name'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_profile) THEN RAISE EXCEPTION 'No such member'; END IF;
  INSERT INTO guild_character_links (character_name, profile_id, linked_by, linked_at) VALUES (v_name, p_profile, auth.uid(), now())
  ON CONFLICT (character_name) DO UPDATE SET profile_id = EXCLUDED.profile_id, linked_by = auth.uid(), linked_at = now();
END $$;
REVOKE ALL ON FUNCTION public.link_character(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_character(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_character(p_character TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND protected) THEN RAISE EXCEPTION 'Raid Leader only'; END IF;
  DELETE FROM guild_character_links WHERE character_name = lower(btrim(coalesce(p_character, '')));
END $$;
REVOKE ALL ON FUNCTION public.unlink_character(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_character(TEXT) TO authenticated;
