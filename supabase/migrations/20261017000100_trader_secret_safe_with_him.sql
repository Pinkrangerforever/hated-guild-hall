-- Migration: Mysterious Trader - "your secret is safe with him"
-- Purpose: the trader is a he; the paid-access message said "them". Only that word changes; the rest of
--          pay_mysterious_trader is as in 20261010000100.
-- Date: 2026-10-17
-- Reverse: re-run pay_mysterious_trader from 20261010000100.

CREATE OR REPLACE FUNCTION public.pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_cost INTEGER := 3000;
  v_user_gold INTEGER;
BEGIN
  IF v_user_id IS NULL OR pay_mysterious_trader.user_id IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  IF EXISTS (SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;

  SELECT pr.gold INTO v_user_gold FROM public.profiles pr WHERE pr.id = v_user_id FOR UPDATE;
  IF v_user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;
  IF v_user_gold < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold', 'current_gold', v_user_gold, 'cost', v_cost);
  END IF;

  PERFORM set_config('app.allow_purchase', 'true', true);
  UPDATE public.profiles pr
  SET gold = pr.gold - v_cost,
      gold_spent_total = COALESCE(pr.gold_spent_total, 0) + v_cost
  WHERE pr.id = v_user_id;
  PERFORM set_config('app.allow_purchase', 'false', true);

  INSERT INTO public.mystery_trader_access (user_id, payment_amount) VALUES (v_user_id, v_cost);
  INSERT INTO public.purchase_log (user_id, purchase_type, amount, description, metadata)
  VALUES (v_user_id, 'dealer_access', v_cost, 'Unlocked Shadowy Dealer - Pet Egg Access',
          jsonb_build_object('trader_cost', v_cost, 'unlocks', 'pet_eggs', 'dealer_name', 'Shadowy Dealer'));

  RETURN jsonb_build_object('success', true, 'message', 'The trader smiles. Your secret is safe with him.',
                            'new_gold', v_user_gold - v_cost, 'eggs_unlocked', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.pay_mysterious_trader(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pay_mysterious_trader(UUID) TO authenticated;
