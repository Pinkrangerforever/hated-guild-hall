-- Migration: Hated TCG card packs and collections
-- Purpose: players spend TCG points on packs; the server rolls the cards so a pull can't be faked.
--   * tcg_cards        the card catalog (rows come from 20261020000200_tcg_card_catalog.sql)
--   * tcg_collection   cards each player owns (count + how many of those are holographic)
--   * tcg_pack_opens   one row per pack opened (what came out), for history / auditing
--   * tcg_open_pack()  costs 100 points, 5 cards, each rolled separately:
--                      Common 64% / Uncommon 20% / Rare 10% / Epic 5% / Legendary 1%; Rare+ cards 2% holographic
-- Date: 2026-10-20
-- Reverse: DROP FUNCTION public.tcg_open_pack(); DROP TABLE public.tcg_pack_opens, public.tcg_collection, public.tcg_cards;

CREATE TABLE IF NOT EXISTS public.tcg_cards (
  id         text PRIMARY KEY,                 -- Hearthstone card id (image: tcg/cards/<id>.webp)
  name       text NOT NULL,
  set_code   text,
  card_class text,
  card_type  text,
  rarity     text NOT NULL CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  cost       int,
  attack     int,
  health     int,
  in_packs   boolean NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS tcg_cards_rarity ON public.tcg_cards (rarity) WHERE in_packs;

CREATE TABLE IF NOT EXISTS public.tcg_collection (
  user_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  card_id  text NOT NULL REFERENCES public.tcg_cards(id),
  count    int NOT NULL DEFAULT 0,
  holo     int NOT NULL DEFAULT 0,
  first_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, card_id)
);

CREATE TABLE IF NOT EXISTS public.tcg_pack_opens (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  at      timestamptz NOT NULL DEFAULT now(),
  cost    int NOT NULL,
  cards   jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS tcg_pack_opens_user ON public.tcg_pack_opens (user_id, at DESC);

ALTER TABLE public.tcg_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_collection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tcg_pack_opens ENABLE ROW LEVEL SECURITY;

-- the catalog is public to members; collections can be browsed by any member (show off your binder); pack history is your own
DROP POLICY IF EXISTS tcg_cards_read ON public.tcg_cards;
CREATE POLICY tcg_cards_read ON public.tcg_cards FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS tcg_collection_read ON public.tcg_collection;
CREATE POLICY tcg_collection_read ON public.tcg_collection FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS tcg_pack_opens_read ON public.tcg_pack_opens;
CREATE POLICY tcg_pack_opens_read ON public.tcg_pack_opens FOR SELECT TO authenticated USING (user_id = auth.uid());

GRANT SELECT ON public.tcg_cards, public.tcg_collection, public.tcg_pack_opens TO authenticated;
GRANT ALL ON public.tcg_cards, public.tcg_collection, public.tcg_pack_opens TO service_role;
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
  END LOOP;

  INSERT INTO tcg_pack_opens (user_id, cost, cards) VALUES (uid, price, pulled);
  RETURN jsonb_build_object('cards', pulled, 'points', acct.points - price);
END;
$$;

REVOKE ALL ON FUNCTION public.tcg_open_pack() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tcg_open_pack() TO authenticated;
