# GitHub Actions CI/CD - Quick Start

## What Was Set Up

✅ **Automatic Supabase migration deployments** using GitHub Actions

- **Staging**: Auto-deploys on push to `staging` branch
- **Production**: Requires manual approval on push to `main` branch
- **Safety Features**: Concurrency control, dry-run validation, comprehensive logging

## Files Created

```
.github/workflows/
├── staging.yml              # Staging deployment workflow
├── prod.yml                 # Production deployment workflow
└── README.md                # Workflow documentation

GITHUB_ACTIONS_SETUP.md      # Complete setup guide (READ THIS FIRST)
scripts/
├── setup-github-secrets.md  # Step-by-step secret configuration
└── verify-github-actions-setup.sh  # Validation script

docs/
└── MIGRATION_WORKFLOW_REFERENCE.md  # Technical reference & examples

supabase/migrations/
└── prod/                    # Directory for production migrations
```

## Quick Start (5 Steps)

### 1. ✅ Workflows Already Created
- `.github/workflows/staging.yml` and `prod.yml` are ready
- No code changes needed

### 2. ⚠️ Set Up GitHub Secrets (Required)
You need to add 8 secrets to GitHub:

**Staging Secrets (4):**
- `SUPABASE_STAGING_PROJECT_REF` = `jucmmnmnbjrzmjrugggl`
- `SUPABASE_STAGING_ACCESS_TOKEN` = (from Supabase)
- `SUPABASE_STAGING_SERVICE_ROLE_KEY` = (from Supabase dashboard)
- `SUPABASE_STAGING_DB_PASSWORD` = (your staging password)

**Production Secrets (4):**
- `SUPABASE_PROD_PROJECT_REF` = `dymlprrudprwyctjqqer`
- `SUPABASE_PROD_ACCESS_TOKEN` = (from Supabase)
- `SUPABASE_PROD_SERVICE_ROLE_KEY` = (from Supabase dashboard)
- `SUPABASE_PROD_DB_PASSWORD` = (your production password)

**How to Add:**
1. Go: https://github.com/Pinkrangerforever/hated-guild-hall/settings/secrets/actions
2. Click "New repository secret" 8 times
3. Add each secret name and value
4. Done!

📖 **Detailed instructions:** See `scripts/setup-github-secrets.md`

### 3. ✅ Create GitHub Environments (Recommended)
Set up environment protection for safer deployments:

1. Go: https://github.com/Pinkrangerforever/hated-guild-hall/settings/environments
2. Create **`staging`** environment
3. Create **`prod`** environment
   - ⚠️ **Enable protection:** Require reviewers (at least 1)
   - Set deployment branches to: `main`

This prevents accidental production deployments.

### 4. ✅ Test the Setup
Create a test migration:

```bash
# For staging
mkdir -p supabase/migrations/staging
echo "-- Test staging migration
CREATE TABLE IF NOT EXISTS test_staging (id BIGSERIAL PRIMARY KEY);
" > supabase/migrations/staging/20261005_test.sql

# Commit and push
git add supabase/migrations/staging/20261005_test.sql
git commit -m "Test: Verify staging workflow"
git push origin staging
```

Then:
1. Go to: https://github.com/Pinkrangerforever/hated-guild-hall/actions
2. Watch the **"Deploy Staging Migrations"** workflow
3. Should show ✅ "successfully deployed"

### 5. ✅ Test Production (With Approval)
```bash
# For production
echo "-- Test production migration
CREATE TABLE IF NOT EXISTS test_prod (id BIGSERIAL PRIMARY KEY);
" > supabase/migrations/prod/20261005_test.sql

# Commit and push to main
git add supabase/migrations/prod/20261005_test.sql
git commit -m "Test: Verify production workflow"
git push origin main
```

Then:
1. Go to: https://github.com/Pinkrangerforever/hated-guild-hall/actions
2. Click the **"Deploy Production Migrations"** workflow run
3. You should see **"Review pending"** button - Click it
4. Select **`prod`** environment
5. Click **"Approve and deploy"**
6. Workflow runs and deploys

## How It Works

### Staging Workflow
```
Push to staging branch
       ↓
Changes in supabase/migrations/staging/
       ↓
Workflow triggers automatically
       ↓
- Install Supabase CLI
- Authenticate with staging secrets
- List migrations
- Apply to STAGING database
- Verify success
       ↓
Done! (No manual approval needed)
```

### Production Workflow
```
Push to main branch
       ↓
Changes in supabase/migrations/prod/
       ↓
Workflow triggers
       ↓
Prepare job: List which migrations will be applied
       ↓
⏸️  WAITING FOR APPROVAL
       ↓
Human reviews migrations and clicks "Approve"
       ↓
Deploy job: Apply to PRODUCTION database
       ↓
✅ Done!
```

## Migration File Format

Create migration files with this naming convention:

```
YYYYMMDD_HHMMSS_description.sql
```

Examples:
- ✅ `20261005_070000_add_user_roles.sql`
- ✅ `20261005_140530_create_audit_table.sql`
- ❌ `migration.sql` (too vague)

## Security Best Practices

✅ **DO:**
- Keep secrets in GitHub (not in code)
- Use different passwords for staging vs prod
- Require reviewers for production
- Rotate tokens every 90 days
- Test migrations on staging first

❌ **DON'T:**
- Commit secrets to repository
- Use same password for staging/prod
- Skip production approval step
- Forget to backup production
- Deploy without testing on staging

## Common Commands

### Test Migration Locally
```bash
# Install Supabase CLI (one-time)
npm install -g supabase

# Link to your project
supabase link --project-ref jucmmnmnbjrzmjrugggl

# Test without applying (dry-run)
supabase db push --dry-run

# Actually apply (if dry-run succeeds)
supabase db push
```

### Check Workflow Status
```bash
# In GitHub Actions tab
https://github.com/Pinkrangerforever/hated-guild-hall/actions
```

### Verify Migrations in Supabase
```bash
# In Supabase Dashboard
https://app.supabase.com
→ Select project
→ SQL Editor
→ Migrations tab
```

## Troubleshooting

### Q: Workflow not running?
A: Check:
- Push is to `staging` or `main` branch
- Files changed in `supabase/migrations/staging/` or `supabase/migrations/prod/`
- Workflow file exists: `.github/workflows/staging.yml` or `prod.yml`

### Q: "Authentication failed" error?
A: Check:
- All 8 secrets are added to GitHub
- Secret names spelled exactly (case-sensitive)
- Values are correct (especially Service Role Key)
- Access token hasn't expired

### Q: Migration failed to apply?
A: Check:
- SQL syntax is correct
- Run `supabase db push --dry-run` locally first
- Check Postgres logs in Supabase dashboard

### Q: Production approval not showing?
A: Check:
- GitHub environment `prod` is created
- Secret names are exactly: `SUPABASE_PROD_*`
- Workflow file has: `environment: prod`

## Next Steps

1. **Read Full Setup Guide:**
   - `GITHUB_ACTIONS_SETUP.md` (comprehensive)

2. **Add GitHub Secrets:**
   - Follow `scripts/setup-github-secrets.md`

3. **Verify Setup:**
   - Run `scripts/verify-github-actions-setup.sh`

4. **Test Workflows:**
   - Create test migration files
   - Push and observe workflow execution

5. **Create Real Migrations:**
   - Add your actual database migrations
   - Follow naming convention
   - Test on staging before production

## Key Files to Know

| File | Purpose |
|------|---------|
| `.github/workflows/staging.yml` | Staging deployment (automatic) |
| `.github/workflows/prod.yml` | Production deployment (approval required) |
| `GITHUB_ACTIONS_SETUP.md` | Complete setup documentation |
| `scripts/setup-github-secrets.md` | Secret configuration steps |
| `scripts/verify-github-actions-setup.sh` | Validation script |
| `docs/MIGRATION_WORKFLOW_REFERENCE.md` | Technical deep-dive |
| `supabase/migrations/staging/` | Staging migrations |
| `supabase/migrations/prod/` | Production migrations |

## Questions?

Check these in order:
1. This document (QUICKSTART_CI_CD.md)
2. `GITHUB_ACTIONS_SETUP.md` (detailed setup)
3. `docs/MIGRATION_WORKFLOW_REFERENCE.md` (technical details)
4. GitHub Actions logs (Actions tab)
5. Supabase logs (Dashboard)

---

**Status:** ✅ Ready to configure

**Next Action:** Add GitHub Secrets (see `scripts/setup-github-secrets.md`)
