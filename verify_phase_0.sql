-- ============================================================================
-- PHASE 0 VERIFICATION SCRIPT
-- Run this on staging database to verify all Phase 0 migrations deployed
-- ============================================================================

-- 1. CHECK NEW RESOURCE COLUMNS IN PROFILES
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '1. Checking profiles columns' AS check_desc;

SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'profiles'
  AND column_name IN ('food', 'food_earned_total', 'food_spent_total',
                       'wood', 'wood_earned_total', 'wood_spent_total')
ORDER BY column_name;

-- 2. CHECK NEW TABLES EXIST
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '2. Checking new tables' AS check_desc;

SELECT
  table_name,
  (SELECT count(*) FROM information_schema.columns c WHERE c.table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_name IN ('pets', 'house', 'house_additions', 'mystery_trader_access')
ORDER BY table_name;

-- 3. DETAILED PETS TABLE SCHEMA
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '3. Pets table columns' AS check_desc;

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'pets'
ORDER BY ordinal_position;

-- 4. DETAILED HOUSE TABLE SCHEMA
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '4. House table columns' AS check_desc;

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'house'
ORDER BY ordinal_position;

-- 5. DETAILED HOUSE_ADDITIONS TABLE SCHEMA
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '5. House additions table columns' AS check_desc;

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'house_additions'
ORDER BY ordinal_position;

-- 6. DETAILED MYSTERY_TRADER_ACCESS TABLE SCHEMA
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '6. Mystery trader access table columns' AS check_desc;

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'mystery_trader_access'
ORDER BY ordinal_position;

-- 7. CHECK RLS IS ENABLED ON NEW TABLES
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '7. RLS enabled status' AS check_desc;

SELECT
  schemaname,
  tablename,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('pets', 'house', 'house_additions', 'mystery_trader_access')
ORDER BY tablename;

-- 8. CHECK RLS POLICIES EXIST
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '8. RLS policies count' AS check_desc;

SELECT
  schemaname,
  tablename,
  count(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('pets', 'house', 'house_additions', 'mystery_trader_access')
GROUP BY schemaname, tablename
ORDER BY tablename;

-- 9. LIST ALL RLS POLICIES
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '9. All RLS policies' AS check_desc;

SELECT
  tablename,
  policyname,
  permissive,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('pets', 'house', 'house_additions', 'mystery_trader_access')
ORDER BY tablename, policyname;

-- 10. CHECK INDEXES CREATED
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '10. Indexes created' AS check_desc;

SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND (tablename IN ('pets', 'house', 'house_additions', 'mystery_trader_access')
       OR indexname LIKE '%food%' OR indexname LIKE '%wood%')
ORDER BY tablename, indexname;

-- 11. CHECK RPC FUNCTIONS EXIST
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '11. RPC functions deployed' AS check_desc;

SELECT
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'feed_pet',
    'pet_action',
    'hatch_egg',
    'name_pet',
    'spend_resource',
    'earn_resource',
    'check_trader_access',
    'pay_mysterious_trader',
    'purchase_pet_egg',
    'initialize_house',
    'upgrade_house',
    'select_backdrop',
    'add_house_addition',
    'toggle_house_addition',
    'get_house_data'
  )
ORDER BY routine_name;

-- 12. COUNT OF EACH RPC FUNCTION
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '12. RPC function count' AS check_desc;

SELECT
  COUNT(*) as total_functions,
  COUNT(CASE WHEN routine_name LIKE '%feed%' OR routine_name LIKE '%pet%' OR routine_name LIKE '%hatch%' OR routine_name LIKE '%name%' THEN 1 END) as pet_functions,
  COUNT(CASE WHEN routine_name LIKE '%trader%' OR routine_name LIKE '%purchase%' THEN 1 END) as trader_functions,
  COUNT(CASE WHEN routine_name LIKE '%house%' OR routine_name LIKE '%backdrop%' OR routine_name LIKE '%addition%' THEN 1 END) as house_functions,
  COUNT(CASE WHEN routine_name LIKE '%resource%' THEN 1 END) as resource_functions
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION';

-- 13. SAMPLE DATA CHECK (if any exists)
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '13. Sample data row counts' AS check_desc;

SELECT 'profiles with resources' as table_name, COUNT(*) as row_count FROM public.profiles WHERE food IS NOT NULL UNION ALL
SELECT 'pets', COUNT(*) FROM public.pets UNION ALL
SELECT 'house', COUNT(*) FROM public.house UNION ALL
SELECT 'house_additions', COUNT(*) FROM public.house_additions UNION ALL
SELECT 'mystery_trader_access', COUNT(*) FROM public.mystery_trader_access;

-- 14. FINAL VERIFICATION SUMMARY
-- ============================================================================
SELECT 'PHASE 0 VERIFICATION' AS test, '14. FINAL SUMMARY' AS check_desc;

SELECT
  'All tables created' as check_item,
  CASE
    WHEN (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('pets', 'house', 'house_additions', 'mystery_trader_access')) = 4
    THEN '✅ PASS'
    ELSE '❌ FAIL'
  END as status
UNION ALL
SELECT
  'All resource columns added to profiles',
  CASE
    WHEN (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'profiles' AND column_name IN ('food', 'food_earned_total', 'food_spent_total', 'wood', 'wood_earned_total', 'wood_spent_total')) = 6
    THEN '✅ PASS'
    ELSE '❌ FAIL'
  END
UNION ALL
SELECT
  'RLS enabled on all new tables',
  CASE
    WHEN (SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('pets', 'house', 'house_additions', 'mystery_trader_access') AND rowsecurity = true) = 4
    THEN '✅ PASS'
    ELSE '❌ FAIL'
  END
UNION ALL
SELECT
  'All RPC functions deployed',
  CASE
    WHEN (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name IN (
      'feed_pet', 'pet_action', 'hatch_egg', 'name_pet', 'spend_resource', 'earn_resource',
      'check_trader_access', 'pay_mysterious_trader', 'purchase_pet_egg', 'initialize_house',
      'upgrade_house', 'select_backdrop', 'add_house_addition', 'toggle_house_addition', 'get_house_data'
    )) = 15
    THEN '✅ PASS'
    ELSE '❌ FAIL'
  END;

-- ============================================================================
-- END OF VERIFICATION SCRIPT
-- ============================================================================
