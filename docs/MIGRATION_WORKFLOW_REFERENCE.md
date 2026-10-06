# Supabase Migration Workflow Reference

This document explains how the automated migration workflows work and how to test them locally.

## Workflow Overview

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Git Repository                           │
│  (GitHub: Pinkrangerforever/hated-guild-hall)              │
└─────────────────────────────────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │             │
                    ▼             ▼
            ┌──────────────┐  ┌──────────────┐
            │   Staging    │  │    Main      │
            │   Branch     │  │   Branch     │
            └──────────────┘  └──────────────┘
                    │             │
                    ▼             ▼
        ┌──────────────────┐  ┌──────────────────┐
        │ staging.yml      │  │ prod.yml         │
        │ (Auto-deploy)    │  │ (Manual approval)│
        └──────────────────┘  └──────────────────┘
                    │             │
                    ▼             ▼
    ┌─────────────────────────────────┐
    │   GitHub Actions - Ubuntu VM    │
    │ - Install Supabase CLI          │
    │ - Authenticate                  │
    │ - Push Migrations               │
    │ - Verify Success                │
    └─────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
         ▼                     ▼
    ┌──────────────────┐  ┌──────────────────┐
    │  STAGING DB      │  │  PRODUCTION DB   │
    │  jucmmnmn...     │  │  dymlprru...     │
    │  Supabase        │  │  Supabase        │
    └──────────────────┘  └──────────────────┘
```

## Workflow Files

### `.github/workflows/staging.yml`

**Trigger:** Push to `staging` branch with changes in `supabase/migrations/staging/**`

**Steps:**
1. Checkout code
2. Setup Node.js
3. Install Supabase CLI
4. Authenticate with Supabase using secrets
5. List pending migrations (dry-run)
6. Push migrations to STAGING database
7. Verify migrations applied
8. Post status message

**Key Features:**
- Automatic on every push (no approval needed)
- Skips if no migration files
- Concurrency group prevents simultaneous runs

### `.github/workflows/prod.yml`

**Trigger:** Push to `main` branch with changes in `supabase/migrations/prod/**`

**Steps:**
1. **Prepare Job:**
   - Checkout code
   - Check for migration files
   - List migrations for review
   
2. **Approval Job:**
   - Waits for manual approval via GitHub Environments
   - Shows which migrations will be applied
   - ⚠️ Requires reviewer approval
   
3. **Deploy Job:**
   - Authenticate with production secrets
   - Display warning (production database)
   - Push migrations to PRODUCTION database
   - Verify migrations applied
   - Post success/failure status

**Key Features:**
- Manual approval required (safer for production)
- Clear separation of concerns (prepare → approval → deploy)
- Concurrency group prevents simultaneous runs
- Failure notifications

---

## Local Testing & Development

### Prerequisites

```bash
# Install Supabase CLI
npm install -g supabase

# Verify installation
supabase --version
```

### Test a Migration Locally

#### 1. Create a Migration File

```bash
# For staging
cat > supabase/migrations/staging/20261005_test_feature.sql << 'EOF'
-- Test migration for staging
CREATE TABLE IF NOT EXISTS test_features (
  id BIGSERIAL PRIMARY KEY,
  feature_name TEXT NOT NULL UNIQUE,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_test_features_active ON test_features(is_active);

COMMENT ON TABLE test_features IS 'Test features for staging environment';
EOF
```

```bash
# For production
cat > supabase/migrations/prod/20261005_production_feature.sql << 'EOF'
-- Production migration
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS 
  email_verified BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_profiles_email_verified 
ON profiles(email_verified);

COMMENT ON COLUMN profiles.email_verified IS 'Tracks whether user email is verified';
EOF
```

#### 2. Link to Supabase Project

```bash
# Link to staging project
supabase link --project-ref jucmmnmnbjrzmjrugggl

# You'll be prompted to enter your database password
# Or use the password flag:
supabase link --project-ref jucmmnmnbjrzmjrugggl \
  --password your-db-password
```

#### 3. Perform Dry-Run (Recommended)

```bash
# Test without applying changes
supabase db push --dry-run

# Output will show:
# - Which migrations it will apply
# - The SQL that will be executed
# - Any validation errors
```

#### 4. Apply Migration (if dry-run succeeds)

```bash
# Actually apply the migrations
supabase db push

# This will:
# - Connect to your project
# - Run the migration files
# - Update the migrations table
# - Verify success
```

#### 5. Verify in Dashboard

```bash
# Check Supabase Dashboard:
1. Go to https://app.supabase.com
2. Select your project
3. Navigate to SQL Editor
4. Click "Migrations" tab
5. Verify your migration appears with status "Success"
```

---

## Supabase CLI Commands Reference

### Authentication

```bash
# Login to Supabase (interactive)
supabase login

# Login with email/password
supabase login -e your-email@example.com

# Logout
supabase logout
```

### Linking Projects

```bash
# Link local project to remote Supabase project
supabase link --project-ref jucmmnmnbjrzmjrugggl

# Link with specific password
supabase link --project-ref jucmmnmnbjrzmjrugggl --password "$DB_PASSWORD"

# Unlink (remove connection)
supabase unlink
```

### Migrations

```bash
# Push migrations to remote database
supabase db push

# Dry-run (show what would be applied without applying)
supabase db push --dry-run

# Push with verbose output
supabase db push -v

# Create new migration from current schema
supabase db pull

# List migrations
supabase migration list --project-ref jucmmnmnbjrzmjrugggl
```

### Status & Logs

```bash
# Show linked project info
supabase status

# Show database logs
supabase logs --project-ref jucmmnmnbjrzmjrugggl postgres

# Show recent activity
supabase migration list --project-ref jucmmnmnbjrzmjrugggl
```

---

## Common Scenarios

### Scenario 1: Fix a Failed Migration

**Problem:** A migration had syntax errors and failed to apply

**Steps:**
1. Create a new migration file with the fix:
   ```bash
   # supabase/migrations/staging/20261005_fix_previous_migration.sql
   -- Fix for previous migration
   ALTER TABLE test_features ADD COLUMN description TEXT;
   ```

2. Test locally:
   ```bash
   supabase db push --dry-run
   ```

3. If dry-run succeeds, push to staging:
   ```bash
   git add supabase/migrations/staging/20261005_fix_previous_migration.sql
   git commit -m "Fix: Correct syntax error in test_features table"
   git push origin staging
   ```

4. Workflow automatically applies it

### Scenario 2: Rollback a Migration

**Problem:** A migration caused issues in staging and needs to be reverted

**Steps:**
1. Create a rollback migration:
   ```bash
   # supabase/migrations/staging/20261005_rollback_broken_feature.sql
   -- Rollback: Remove test_features table
   DROP TABLE IF EXISTS test_features CASCADE;
   ```

2. Test and push normally

3. For production, follow same process but with `supabase/migrations/prod/`

### Scenario 3: Migrate Data Safely

**Problem:** Need to add a required column but existing rows don't have values

**Solution - Two Migration Approach:**

Migration 1 - Add column with default:
```sql
-- Step 1: Add column with default value
ALTER TABLE profiles ADD COLUMN status TEXT DEFAULT 'active';
```

Migration 2 - Add constraint (next deployment):
```sql
-- Step 2: Make column NOT NULL (after verifying data)
ALTER TABLE profiles ALTER COLUMN status SET NOT NULL;
```

This prevents "NOT NULL violation" errors.

### Scenario 4: Complex Schema Change

**Problem:** Refactoring multiple tables

**Best Practice:**
```sql
-- Use transactions and comments
BEGIN;

-- Step 1: Create new table with new structure
CREATE TABLE users_v2 AS
SELECT id, LOWER(email) as email, created_at FROM users;

-- Step 2: Migrate data if needed
UPDATE users_v2 SET email = LOWER(email);

-- Step 3: Rename tables
ALTER TABLE users RENAME TO users_old;
ALTER TABLE users_v2 RENAME TO users;

-- Step 4: Recreate indexes
CREATE INDEX idx_users_email ON users(email);

-- Step 5: Update foreign keys
ALTER TABLE posts DROP CONSTRAINT posts_user_id_fkey;
ALTER TABLE posts ADD CONSTRAINT posts_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

COMMIT;
```

---

## Performance Considerations

### Migration Timing

- **Migrations run sequentially** (one at a time)
- **Average migration time:** 100-500ms per migration
- **Large data migrations:** Can take minutes
  - Consider during off-peak hours
  - Test duration locally first

### Optimization Tips

```sql
-- ❌ Avoid in production
ALTER TABLE large_table ADD COLUMN new_col INTEGER; -- Locks table

-- ✅ Better
ALTER TABLE large_table ADD COLUMN new_col INTEGER DEFAULT 0;
-- Then update in batches if needed

-- ❌ Avoid complex transactions
BEGIN;
  -- 1000 inserts
COMMIT;

-- ✅ Better
INSERT INTO staging_data SELECT * FROM backup
  WHERE created_at > NOW() - INTERVAL '1 day';
```

---

## Troubleshooting Guide

### Workflow Errors

#### "Authentication failed"
```
Error: Could not authenticate with Supabase
```
- Check secrets are correctly set
- Verify Access Token hasn't expired
- Regenerate token and update secret

#### "Project not found"
```
Error: Project "xxx" not found
```
- Verify PROJECT_REF is correct
- Check you're using right Supabase account
- Confirm project still exists in dashboard

#### "Migration failed: syntax error"
```
Error: syntax error at or near "CREATE"
```
- Check SQL syntax is correct
- Test locally first: `supabase db push --dry-run`
- Verify for PostgreSQL compatibility (not MySQL)

#### "Too many pending migrations"
```
Warning: 50 pending migrations
```
- This is normal for first deployment
- Workflow will apply all of them
- Monitor in dashboard

#### "Workflow not triggering"
- Check branch name (exactly `staging` or `main`)
- Verify file changes are in correct path:
  - `supabase/migrations/staging/*.sql` or
  - `supabase/migrations/prod/*.sql`
- Check workflow file syntax: `.github/workflows/staging.yml`

### Database Issues

#### "Column already exists"
```sql
-- Use IF NOT EXISTS
ALTER TABLE users ADD COLUMN IF NOT EXISTS new_field TEXT;
```

#### "Constraint violation"
```sql
-- Add constraint safely
ALTER TABLE users ADD CONSTRAINT valid_email
  CHECK (email ~* '^[^@]+@[^@]+\.[^@]+$')
  NOT VALID;

ALTER TABLE users VALIDATE CONSTRAINT valid_email;
```

#### "Permission denied"
- Check database user has proper permissions
- Verify password is correct
- Check IP whitelist (if applicable)

---

## Monitoring Migrations

### In GitHub Actions

1. Go to: https://github.com/Pinkrangerforever/hated-guild-hall/actions
2. Click on workflow run
3. Click on job to see details
4. Check logs for success/error messages

### In Supabase Dashboard

1. Go to: https://app.supabase.com
2. Select project
3. Click **SQL Editor**
4. Click **Migrations** tab
5. View migration history and status

### Logs to Check

```bash
# Database logs (if SSH access available)
supabase logs --project-ref jucmmnmnbjrzmjrugggl postgres

# Function logs (for PLpgSQL functions)
supabase logs --project-ref jucmmnmnbjrzmjrugggl functions
```

---

## Best Practices Summary

### Before Pushing

- [ ] Test locally: `supabase db push --dry-run`
- [ ] Review SQL syntax and logic
- [ ] Check for breaking changes
- [ ] Verify idempotent (safe to run twice)
- [ ] Add meaningful comments to migration

### Migration File Naming

Format: `YYYYMMDD_HHmmss_description.sql`

Examples:
- ✅ `20261005_070530_add_user_profile_fields.sql`
- ✅ `20261005_120000_create_audit_log_table.sql`
- ❌ `migration.sql` (too vague)
- ❌ `20261005_update.sql` (unclear purpose)

### Code Review

- Review SQL changes in pull request
- Ask: "Is this safe for production?"
- Check for data loss risks
- Verify indexes added for new columns
- Confirm performance impact

### Deployment

- Staging: Push, observe, iterate
- Production: Plan carefully, approve once, monitor closely
- Always have rollback plan ready
- Document what changed and why

---

## References

- [Supabase Migrations Guide](https://supabase.com/docs/guides/cli/local-development#database-migrations)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Supabase CLI Reference](https://supabase.com/docs/reference/cli/usage)
