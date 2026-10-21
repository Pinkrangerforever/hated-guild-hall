-- Migration: Hated TCG legendary feed
-- Purpose: every Legendary or holographic card pulled from a pack is recorded in tcg_highlights, which the home
--          page shows as the guild's "Legendary Pulls" feed. tcg_open_pack() is replaced to write those rows.
-- Date: 2026-10-20
-- Reverse: DROP TABLE public.tcg_highlights; then re-run tcg_open_pack() from 20261020000100_tcg_packs.sql

CREATE TABLE IF NOT EXISTS public.tcg_highlights (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  card_id text NOT NULL REFERENCES public.tcg_cards(id),
  rarity  text NOT NULL,
  holo    boolean NOT NULL DEFAULT false,
  at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tcg_highlights_at ON public.tcg_highlights (at DESC);
ALTER TABLE public.tcg_highlights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tcg_highlights_read ON public.tcg_highlights;
CREATE POLICY tcg_highlights_read ON public.tcg_highlights FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.tcg_highlights TO authenticated;
GRANT ALL ON public.tcg_highlights TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

CREATE OR REPLACE FUNCTION public.tcg_open_pack()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid     uuid := auth.uid();
  price   constant int := 100;
  acct    record;
  roll    double precision;
  rar     text;
  cid     text;
  shiny   boolean;
  had     int;
  pulled  jsonb := '[]'::jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in first'; END IF;
  SELECT points, banned INTO acct FROM tcg_accounts WHERE user_id = uid FOR UPDATE;
  IF NOT FOUND OR acct.points < price THEN RAISE EXCEPTION 'not enough points (a pack is % points)', price; END IF;
  IF acct.banned THEN RAISE EXCEPTION 'your TCG account is suspended'; END IF;

  UPDATE tcg_accounts SET points = points - price, updated_at = now() WHERE user_id = uid;

  FOR i IN 1..5 LOOP
    roll := random();
    rar := CASE WHEN roll < 0.01 THEN 'legendary' WHEN roll < 0.06 THEN 'epic' WHEN roll < 0.16 THEN 'rare'
                WHEN roll < 0.36 THEN 'uncommon' ELSE 'common' END;
    SELECT id INTO cid FROM tcg_cards WHERE rarity = rar AND in_packs ORDER BY random() LIMIT 1;
    IF cid IS NULL THEN RAISE EXCEPTION 'the card catalog is empty'; END IF;
    shiny := rar IN ('rare', 'epic', 'legendary') AND random() < 0.02;
    SELECT count INTO had FROM tcg_collection WHERE user_id = uid AND card_id = cid;
    INSERT INTO tcg_collection (user_id, card_id, count, holo) VALUES (uid, cid, 1, CASE WHEN shiny THEN 1 ELSE 0 END)
      ON CONFLICT (user_id, card_id) DO UPDATE SET count = tcg_collection.count + 1, holo = tcg_collection.holo + EXCLUDED.holo;
    pulled := pulled || jsonb_build_object('id', cid, 'rarity', rar, 'holo', shiny, 'new', coalesce(had, 0) = 0);
    IF rar = 'legendary' OR shiny THEN
      INSERT INTO tcg_highlights (user_id, card_id, rarity, holo) VALUES (uid, cid, rar, shiny);
    END IF;
  END LOOP;

  INSERT INTO tcg_pack_opens (user_id, cost, cards) VALUES (uid, price, pulled);
  RETURN jsonb_build_object('cards', pulled, 'points', acct.points - price);
END;
$$;

REVOKE ALL ON FUNCTION public.tcg_open_pack() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tcg_open_pack() TO authenticated;
