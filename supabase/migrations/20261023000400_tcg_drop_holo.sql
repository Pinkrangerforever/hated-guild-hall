-- Migration: Hated TCG card drops can be holographic
-- Purpose: a dropped Rare, Epic, Legendary or hero card is holographic 1 in 50 (2%, like packs), rolled with the drop
--          (drops.ts / HatedTCGDrops.lua). tcg_add_drops now adds holo copies to the collection and puts holo drops
--          on the Legendary Pulls feed too.
-- Date: 2026-10-23
-- Reverse: re-run 20261023000300's CREATE FUNCTION tcg_add_drops.

-- p_drops: [{ card_id, kill_key, hero, holo, npc, char, rarity, at }] -> the ones that were new (a kill drops once)
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
      INSERT INTO tcg_collection (user_id, card_id, count, holo) VALUES (p_user, d->>'card_id', 1, CASE WHEN COALESCE((d->>'holo')::boolean, false) THEN 1 ELSE 0 END)
        ON CONFLICT (user_id, card_id) DO UPDATE SET count = tcg_collection.count + 1, holo = tcg_collection.holo + EXCLUDED.holo;
      IF d->>'rarity' = 'legendary' OR COALESCE((d->>'hero')::boolean, false) OR COALESCE((d->>'holo')::boolean, false) THEN
        INSERT INTO tcg_highlights (user_id, card_id, rarity, holo) VALUES (p_user, d->>'card_id', d->>'rarity', COALESCE((d->>'holo')::boolean, false));
      END IF;
      added := added || (d || jsonb_build_object('new', COALESCE(had, 0) = 0));
    END IF;
    ok := NULL; had := NULL;
  END LOOP;
  RETURN added;
END $$;
REVOKE ALL ON FUNCTION public.tcg_add_drops(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tcg_add_drops(uuid, jsonb) TO service_role;
