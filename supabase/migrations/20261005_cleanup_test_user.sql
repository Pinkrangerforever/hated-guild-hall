-- Migration: Remove staging test user
-- Purpose: Clean up test user created for staging environment verification
-- Date: 2026-10-05
-- Reverse: Recreate auth.users and profiles entries if needed (see 20261005_190731_add_staging_test_user.sql)

-- First delete from profiles (foreign key constraint)
DELETE FROM profiles WHERE id = '99999999-9999-9999-9999-999999999999';

-- Then delete from auth.users
DELETE FROM auth.users WHERE id = '99999999-9999-9999-9999-999999999999';
