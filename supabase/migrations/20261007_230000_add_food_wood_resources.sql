-- Migration: Add Food and Wood resources to profiles table
-- Purpose: Track Food and Wood currencies with earned/spent totals like gold
-- Date: 2026-10-07

-- Add Food columns
ALTER TABLE public.profiles ADD COLUMN food INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN food_earned_total INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN food_spent_total INTEGER DEFAULT 0;

-- Add Wood columns
ALTER TABLE public.profiles ADD COLUMN wood INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN wood_earned_total INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN wood_spent_total INTEGER DEFAULT 0;

-- Create index for resource lookups
CREATE INDEX idx_profiles_food ON public.profiles(food);
CREATE INDEX idx_profiles_wood ON public.profiles(wood);
