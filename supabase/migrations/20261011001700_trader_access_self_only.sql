-- Migration: check_trader_access only answers for the signed-in player
-- Purpose: it took any user id and anyone (even signed out) could call it, so the dealer's "secret"
--          list of customers was enumerable. The parameter is kept for compatibility but ignored.
-- Date: 2026-10-11
-- Reverse: re-create check_trader_access from the 2026-10-10 schema backup.

CREATE OR REPLACE FUNCTION public.check_trader_access(user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('has_access', false, 'message', 'No access');
  END IF;
  SELECT EXISTS (SELECT 1 FROM mystery_trader_access mta WHERE mta.user_id = auth.uid()) INTO v_has;
  RETURN jsonb_build_object('has_access', v_has, 'message', CASE WHEN v_has THEN 'Access granted' ELSE 'No access' END);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.check_trader_access(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_trader_access(UUID) TO authenticated;
