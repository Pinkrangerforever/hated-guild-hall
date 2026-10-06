-- Migration: Add staging test user for environment separation verification
-- Purpose: Insert a test user to verify staging and prod databases are completely separate
-- Date: 2026-10-05

INSERT INTO profiles (
  id, discord_username, character_name, role, created_at, protected, gold,
  last_gold_claim_at, discord_rank_level, gold_earned_total, gold_spent_total
)
VALUES (
  '99999999-9999-9999-9999-999999999999',
  'STAGING_TEST_USER',
  'Test Alpha Chad',
  'member',
  NOW(),
  false,
  99999,
  NOW(),
  0,
  99999,
  0
)
ON CONFLICT DO NOTHING;
