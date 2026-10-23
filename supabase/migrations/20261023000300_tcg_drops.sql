-- Migration: Hated TCG card drops from kills
-- Purpose: kills can drop cards in game (addon 3.8, HatedTCGDrops.lua). tcg-sync rolls each drop again from the
--          kill's spawn id with the same tables (supabase/functions/tcg-sync/drops.ts) and adds the card here:
--   * tcg_drops      every card that dropped from a kill (one per kill per account: kill_key is the spawn id, or a
--                    boss's own key); hero = it was the 1-in-100 class hero roll
--   * tcg_npc_tags   what each player's addon said a creature is (its drop group and class, e.g. "t.BEAST|"); once
--                    2+ other players agree on a creature, a different claim about it drops nothing
--   * tcg_add_drops  (server only) adds the drops to the collection, logs them, and puts legendaries and heroes on
--                    the home page's Legendary Pulls feed
-- Date: 2026-10-23
-- Reverse: DROP FUNCTION public.tcg_add_drops(uuid, jsonb); DROP TABLE public.tcg_drops, public.tcg_npc_tags;

CREATE TABLE IF NOT EXISTS public.tcg_drops (
  id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  card_id  text NOT NULL REFERENCES public.tcg_cards(id),
  kill_key text NOT NULL,
  hero     boolean NOT NULL DEFAULT false,
  npc      int,
  char     text,
  rarity   text NOT NULL,
  at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, kill_key, hero)
);
CREATE INDEX IF NOT EXISTS tcg_drops_user ON public.tcg_drops (user_id, at DESC);
ALTER TABLE public.tcg_drops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tcg_drops_read ON public.tcg_drops;
CREATE POLICY tcg_drops_read ON public.tcg_drops FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT SELECT ON public.tcg_drops TO authenticated;
GRANT ALL ON public.tcg_drops TO service_role;

CREATE TABLE IF NOT EXISTS public.tcg_npc_tags (
  npc_key int  NOT NULL,          -- creature id, or minus the encounter id for a boss
  tag     text NOT NULL,          -- "<drop group>|<class>"
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (npc_key, tag, user_id)
);
ALTER TABLE public.tcg_npc_tags ENABLE ROW LEVEL SECURITY;   -- no policies: only the server uses it
GRANT ALL ON public.tcg_npc_tags TO service_role;

-- p_drops: [{ card_id, kill_key, hero, npc, char, rarity, at }] -> the ones that were new (a kill drops once)
CREATE OR REPLACE FUNCTION public.tcg_add_drops(p_user uuid, p_drops jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d jsonb; added jsonb := '[]'::jsonb; had int; ok boolean;
BEGIN
  FOR d IN SELECT * FROM jsonb_array_elements(COALESCE(p_drops, '[]'::jsonb)) LOOP
    INSERT INTO tcg_drops (user_id, card_id, kill_key, hero, npc, char, rarity, at)
    VALUES (p_user, d->>'card_id', d->>'kill_key', COALESCE((d->>'hero')::boolean, false), (d->>'npc')::int, d->>'char', d->>'rarity',
            COALESCE(to_timestamp((d->>'at')::bigint), now()))
    ON CONFLICT (user_id, kill_key, hero) DO NOTHING
    RETURNING true INTO ok;
    IF ok THEN
      SELECT count INTO had FROM tcg_collection WHERE user_id = p_user AND card_id = d->>'card_id';
      INSERT INTO tcg_collection (user_id, card_id, count, holo) VALUES (p_user, d->>'card_id', 1, 0)
        ON CONFLICT (user_id, card_id) DO UPDATE SET count = tcg_collection.count + 1;
      IF d->>'rarity' = 'legendary' OR COALESCE((d->>'hero')::boolean, false) THEN
        INSERT INTO tcg_highlights (user_id, card_id, rarity, holo) VALUES (p_user, d->>'card_id', d->>'rarity', false);
      END IF;
      added := added || (d || jsonb_build_object('new', COALESCE(had, 0) = 0));
    END IF;
    ok := NULL; had := NULL;
  END LOOP;
  RETURN added;
END $$;
REVOKE ALL ON FUNCTION public.tcg_add_drops(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tcg_add_drops(uuid, jsonb) TO service_role;
