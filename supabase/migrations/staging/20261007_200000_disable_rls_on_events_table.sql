-- Migration: Disable RLS on events table for public read access
-- Purpose: Allow ALL users (authenticated and anonymous) to read events without restrictions
-- Date: 2026-10-07

-- Disable RLS on the events table entirely
-- This allows anyone to read events without needing a policy
ALTER TABLE public.events DISABLE ROW LEVEL SECURITY;

-- Explicitly grant SELECT to everyone
GRANT SELECT ON public.events TO anon;
GRANT SELECT ON public.events TO authenticated;
GRANT SELECT ON public.events TO public;
