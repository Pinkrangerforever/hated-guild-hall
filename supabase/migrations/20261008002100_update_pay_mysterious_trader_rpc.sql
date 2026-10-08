-- Migration: Update pay_mysterious_trader RPC to log purchase
-- Purpose: Track dealer access purchase in purchase_log table
-- Date: 2026-10-08

CREATE OR REPLACE FUNCTION pay_mysterious_trader(user_id UUID)
RETURNS jsonb AS $$
DECLARE
  user_gold INTEGER;
  cost INTEGER := 3000;
  already_paid BOOLEAN;
BEGIN
  -- Check if already paid
  SELECT EXISTS(SELECT 1 FROM public.mystery_trader_access WHERE user_id = user_id)
  INTO already_paid;

  IF already_paid THEN
    RETURN jsonb_build_object('success', false, 'error', 'You already know the trader''s secret');
  END IF;

  -- Get gold balance
  SELECT gold INTO user_gold FROM public.profiles WHERE id = user_id;

  IF user_gold IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;

  -- Validate gold balance
  IF user_gold < cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient gold',
      'current_gold', user_gold,
      'cost', cost
    );
  END IF;

  -- Deduct gold
  UPDATE public.profiles
  SET gold = gold - cost, gold_spent_total = gold_spent_total + cost, updated_at = now()
  WHERE id = user_id;

  -- Record trader access
  INSERT INTO public.mystery_trader_access (user_id, payment_amount)
  VALUES (user_id, cost);

  -- Log purchase in purchase_log table
  INSERT INTO public.purchase_log (user_id, purchase_type, amount, description, metadata)
  VALUES (
    user_id,
    'dealer_access',
    cost,
    'Unlocked Shadowy Dealer - Pet Egg Access',
    jsonb_build_object(
      'trader_cost', cost,
      'unlocks', 'pet_eggs',
      'dealer_name', 'Shadowy Dealer'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'The trader smiles. Your secret is safe with them.',
    'new_gold', user_gold - cost,
    'eggs_unlocked', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
