-- Migration: Hated TCG bulk opening
-- Purpose: open several packs at once (the shop's "Bulk open"). Checks the whole cost up front, then opens each pack
--          with tcg_open_pack() (so odds, holo rolls, history and the Legendary feed all work the same) in one transaction.
-- Date: 2026-10-20
-- Reverse: DROP FUNCTION public.tcg_open_packs(int);

CREATE OR REPLACE FUNCTION public.tcg_open_packs(n int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid    uuid := auth.uid();
  pts    int;
  one    jsonb;
  pulled jsonb := '[]'::jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in first'; END IF;
  IF n IS NULL OR n < 1 OR n > 50 THEN RAISE EXCEPTION 'open between 1 and 50 packs at a time'; END IF;
  SELECT points INTO pts FROM tcg_accounts WHERE user_id = uid FOR UPDATE;
  IF NOT FOUND OR pts < n * 100 THEN RAISE EXCEPTION 'not enough points for % packs (% needed)', n, n * 100; END IF;
  FOR i IN 1..n LOOP
    one := tcg_open_pack();
    pulled := pulled || (one -> 'cards');
  END LOOP;
  RETURN jsonb_build_object('cards', pulled, 'points', (one ->> 'points')::int, 'packs', n);
END;
$$;

REVOKE ALL ON FUNCTION public.tcg_open_packs(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tcg_open_packs(int) TO authenticated;
