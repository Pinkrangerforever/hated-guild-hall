-- Migration: Create mystery_trader_access table
-- Purpose: Track which users have discovered and paid the mysterious trader (unlocks eggs)
-- Date: 2026-10-07

CREATE TABLE public.mystery_trader_access (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  paid_at TIMESTAMP WITH TIME ZONE DEFAULT now(), -- When they paid 3000g
  payment_amount INTEGER DEFAULT 3000, -- Cost to unlock
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.mystery_trader_access ENABLE ROW LEVEL SECURITY;

-- Create indexes
CREATE INDEX idx_mystery_trader_paid_at ON public.mystery_trader_access(paid_at);

-- Policy 1: Users can see their own access status
CREATE POLICY "Users can view own trader access"
  ON public.mystery_trader_access FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Policy 2: System RPC only can insert/update (when payment is processed)
-- (No direct INSERT/UPDATE allowed from clients)
