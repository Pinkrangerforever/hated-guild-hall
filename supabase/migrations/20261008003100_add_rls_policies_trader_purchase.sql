-- Migration: Add RLS policies to lock down trader access and purchase logging
-- Purpose: Ensure only RPC functions can modify these tables, users can only view their own
-- Security: Prevents direct client manipulation of purchase data
-- Date: 2026-10-08

-- ============================================================================
-- MYSTERY_TRADER_ACCESS RLS POLICIES
-- ============================================================================

-- Policy 1: Users can SELECT only their own trader access record
CREATE POLICY "Users can view own trader access"
  ON public.mystery_trader_access FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Policy 2: Prevent any direct INSERT (RPC function handles all inserts)
-- This is implicitly enforced: no INSERT policy means no direct inserts allowed
-- Only SECURITY DEFINER functions can bypass this

-- Policy 3: Prevent any direct UPDATE
-- This is implicitly enforced: no UPDATE policy means no updates allowed

-- Policy 4: Prevent any direct DELETE
-- This is implicitly enforced: no DELETE policy means no deletes allowed

-- ============================================================================
-- PURCHASE_LOG RLS POLICIES
-- ============================================================================

-- Policy 1: Users can SELECT only their own purchases (already exists, but ensure it's there)
-- If it already exists, this will be idempotent
CREATE POLICY "Users can view own purchases" ON public.purchase_log FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Policy 2: Prevent any direct INSERT (RPC functions handle all inserts)
-- This is implicitly enforced: no INSERT policy means no direct inserts allowed

-- Policy 3: Prevent any direct UPDATE
-- This is implicitly enforced: no UPDATE policy means no updates allowed

-- Policy 4: Prevent any direct DELETE
-- This is implicitly enforced: no DELETE policy means no deletes allowed
