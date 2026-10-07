-- Migration: Add active_name_border column to profiles table
-- Purpose: Allow users to select which roster name border to display

ALTER TABLE public.profiles
ADD COLUMN active_name_border uuid DEFAULT NULL REFERENCES public.shop_items(id);

-- Add comment explaining the column
COMMENT ON COLUMN public.profiles.active_name_border IS 'User''s selected roster name border (shop_items.id). NULL means no active border selection.';
