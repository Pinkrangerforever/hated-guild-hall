-- Migration: Remove updated_at reference from pay_mysterious_trader
-- Purpose: profiles table does not have updated_at column - this reference causes error
-- Date: 2026-10-08

DROP FUNCTION IF EXISTS public.pay_mysterious_trader(UUID) CASCADE;

CREATE OR REPLACE FUNCTION pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  v_user_id UUID := user_id;
  user_gold INTEGER;
  cost INTEGER := 3000;
  already_paid BOOLEAN;
BEGIN
  IF auth.uid() != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access mta WHERE mta.user_id = v_user_id)
  INTO already_paid;
  IF already_paid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;
  SELECT gold INTO user_gold FROM public.profiles WHERE id = v_user_id;
  IF user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;
  IF user_gold < cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold', 'current_gold', user_gold, 'cost', cost);
  END IF;
  UPDATE public.profiles SET gold = gold - cost, gold_spent_total = gold_spent_total + cost WHERE id = v_user_id;
  INSERT INTO public.mystery_trader_access (user_id, payment_amount) VALUES (v_user_id, cost);
  INSERT INTO public.purchase_log (user_id, purchase_type, amount, description, metadata) VALUES (v_user_id, 'dealer_access', cost, 'Unlocked Shadowy Dealer - Pet Egg Access', jsonb_build_object('trader_cost', cost, 'unlocks', 'pet_eggs', 'dealer_name', 'Shadowy Dealer'));
  RETURN jsonb_build_object('success', true, 'message', 'The trader smiles. Your secret is safe with them.', 'new_gold', user_gold - cost, 'eggs_unlocked', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
