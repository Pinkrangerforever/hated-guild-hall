-- Migration: a Soft Res link on raid events
-- Purpose: when scheduling a Raid-type event the creator can paste its Soft Res link (softres.it etc.); the event
--          popup shows it under the date and time.
-- Date: 2026-10-23
-- Reverse: ALTER TABLE public.events DROP COLUMN softres_url;

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS softres_url text;
