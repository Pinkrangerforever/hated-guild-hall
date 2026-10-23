-- Migration: event types + the spec each player brings
-- Purpose: events get a type (raid / holiday / event / notification) chosen when they're scheduled; on raid and event
--          types a player picks the class spec they're bringing, and it shows beside their name on the Going list.
-- Date: 2026-10-23
-- Reverse: ALTER TABLE public.events DROP COLUMN kind; ALTER TABLE public.rsvps DROP COLUMN class_key, DROP COLUMN spec_key;

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'event';
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_kind_check;
ALTER TABLE public.events ADD CONSTRAINT events_kind_check CHECK (kind IN ('raid', 'holiday', 'event', 'notification'));

ALTER TABLE public.rsvps ADD COLUMN IF NOT EXISTS class_key text;
ALTER TABLE public.rsvps ADD COLUMN IF NOT EXISTS spec_key text;
