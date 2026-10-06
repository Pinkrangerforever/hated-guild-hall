-- Migration: Add staging test user for environment separation verification
-- Purpose: Insert a test user to verify staging and prod databases are completely separate
-- Date: 2026-10-05

-- First create the user in auth.users
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES (
  '99999999-9999-9999-9999-999999999999',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'staging-test@example.com',
  'test_password_hash',
  NOW(),
  NOW(),
  NOW(),
  '{"provider":"discord","providers":["discord"]}',
  '{"avatar_url":"https://example.com/avatar.png","name":"staging_test_user","email":"staging-test@example.com"}'
) ON CONFLICT DO NOTHING;

-- Then create the profile
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
