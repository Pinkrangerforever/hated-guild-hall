# GitHub Actions CI/CD Setup for Supabase Migrations

This guide walks you through setting up automated Supabase database migrations using GitHub Actions.

## Overview

The CI/CD pipeline automates migrations for two environments:
- **Staging**: Automatic deployment on push to `staging` branch
- **Production**: Requires manual approval on push to `main` branch (safer)

### Workflow Paths
- Staging migrations: `supabase/migrations/staging/*.sql`
- Production migrations: `supabase/migrations/prod/*.sql`

---

## Step 1: Gather Required Information

Before setting up GitHub Secrets, collect the following information:

### For Staging Environment (STAGING Supabase Project)
- **Project Reference ID**: `jucmmnmnbjrzmjrugggl`
- **Project URL**: `https://jucmmnmnbjrzmjrugggl.supabase.co`
- **Database Password**: (Your staging database password)
- **Service Role Key**: (Available in Supabase dashboard)
- **Access Token**: (Generated from Supabase CLI)

### For Production Environment (PROD Supabase Project)
- **Project Reference ID**: `dymlprrudprwyctjqqer`
- **Project URL**: `https://dymlprrudprwyctjqqer.supabase.co`
- **Database Password**: (Your production database password)
- **Service Role Key**: (Available in Supabase dashboard)
- **Access Token**: (Generated from Supabase CLI)

---

## Step 2: Get Service Role Keys from Supabase Dashboard

### For Each Supabase Project:

1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select the project (STAGING or PROD)
3. Navigate to **Settings** → **API**
4. Copy the **Service Role Key** (⚠️ Keep this secret!)
   - This is different from the Public Key
   - Make sure you're copying the correct "service_role" key

---

## Step 3: Generate Supabase CLI Access Token

### Local Setup (One-time):
```bash
# If not already installed
npm install -g supabase

# Log in to Supabase
supabase login

# Follow the browser prompt to authenticate
# Accept the prompt asking for access
```

This creates an access token locally. Retrieve it:
```bash
# Check your local config (for reference only - we'll create a new one)
cat ~/.supabase/access-token
```

### Generate Access Token for GitHub (Recommended):
You can also generate a personal access token directly:
1. Go to [Supabase Account Settings](https://app.supabase.com/account/tokens)
2. Click **Generate new token**
3. Name it: `github-actions-ci-cd`
4. Keep the token for Step 5

---

## Step 4: Create GitHub Environments

GitHub Environments allow you to set branch protection rules and secrets per environment.

### Create Staging Environment:

1. Go to your GitHub repo: `https://github.com/Pinkrangerforever/hated-guild-hall`
2. Click **Settings** → **Environments**
3. Click **New environment**
4. Name: `staging`
5. Click **Configure environment**
6. Optional: Enable branch protection (recommended):
   - Check **Required reviewers**: Set to at least 1 person
   - Check **Deployment branches**: Restrict to `staging`
7. Click **Save protection rules**

### Create Production Environment:

1. Repeat the above steps
2. Name: `prod`
3. **STRONGLY RECOMMENDED**: Set up protection:
   - ✅ Check **Required reviewers**: Set to at least 1 person (preferably yourself + a team member)
   - ✅ Check **Deployment branches**: Restrict to `main`
   - This prevents accidental prod deployments

---

## Step 5: Add GitHub Secrets

GitHub Secrets are encrypted and only available to Actions workflows.

### Add Staging Secrets:

Go to **Settings** → **Secrets and variables** → **Actions**

Click **New repository secret** and add each:

| Secret Name | Value | Notes |
|-------------|-------|-------|
| `SUPABASE_STAGING_PROJECT_REF` | `jucmmnmnbjrzmjrugggl` | Your staging project ID |
| `SUPABASE_STAGING_ACCESS_TOKEN` | `sbp_xxxxxxxxxxxxx` | From Supabase account settings |
| `SUPABASE_STAGING_SERVICE_ROLE_KEY` | `eyJhbGc...` | From Supabase dashboard → Settings → API |
| `SUPABASE_STAGING_DB_PASSWORD` | `your-password` | Your staging database password |

### Add Production Secrets:

Click **New repository secret** and add each:

| Secret Name | Value | Notes |
|-------------|-------|-------|
| `SUPABASE_PROD_PROJECT_REF` | `dymlprrudprwyctjqqer` | Your production project ID |
| `SUPABASE_PROD_ACCESS_TOKEN` | `sbp_xxxxxxxxxxxxx` | From Supabase account settings |
| `SUPABASE_PROD_SERVICE_ROLE_KEY` | `eyJhbGc...` | From Supabase dashboard → Settings → API |
| `SUPABASE_PROD_DB_PASSWORD` | `your-password` | Your production database password |

**⚠️ SECURITY CHECKLIST:**
- [ ] Secrets use production/staging values (never cross-environments)
- [ ] Service Role Keys are from the correct project
- [ ] No secrets are committed to the repo
- [ ] Access Tokens have expiration dates (rotate every 90 days)
- [ ] Only necessary GitHub Actions have access to secrets

---

## Step 6: Test the Workflows

### Test Staging Workflow:

1. Create a new migration file:
```bash
# Create a test migration
echo "-- Test migration for staging
SELECT 'Staging deployment test' as message;" > supabase/migrations/staging/20261005_test.sql
```

2. Commit and push to staging:
```bash
git add supabase/migrations/staging/20261005_test.sql
git commit -m "Test: Add staging migration for CI/CD verification"
git push origin staging
```

3. Watch the workflow:
   - Go to **Actions** tab in GitHub
   - Click on the **Deploy Staging Migrations** workflow
   - Watch the job execute
   - It should complete successfully ✅

4. Verify in Supabase Dashboard:
   - Go to [Supabase Dashboard](https://app.supabase.com)
   - Select STAGING project
   - Check **SQL Editor** → **Migrations** to see the applied migration

### Test Production Workflow (Manual Approval):

1. Create a test migration for production:
```bash
echo "-- Test migration for production
SELECT 'Production deployment test' as message;" > supabase/migrations/prod/20261005_test.sql
```

2. Commit and push to main:
```bash
git add supabase/migrations/prod/20261005_test.sql
git commit -m "Test: Add production migration for CI/CD verification"
git push origin main
```

3. Watch the workflow:
   - Go to **Actions** tab in GitHub
   - Click on the **Deploy Production Migrations** workflow
   - You should see a "Prepare Production Deployment" job ✅
   - Then a yellow "Review pending" status - **Click "Review deployments"**
   - Select **prod** environment and click **Approve and deploy**
   - The deployment job will then execute

4. Verify in Supabase Dashboard:
   - Select PROD project
   - Check **SQL Editor** → **Migrations** to see the applied migration

---

## Step 7: Best Practices & Safety Measures

### Prevent Accidental Deployments:

1. **Branch Protection Rules** (in GitHub Settings → Branches):
   - Require pull request reviews before merging to `main`
   - Require status checks to pass (workflows)
   - Require branches to be up to date

2. **GitHub Environments Protection** (already set in Step 4):
   - Staging: Optional reviewers
   - Production: ⚠️ **REQUIRED reviewers** (at least 1)

3. **Concurrency Control**:
   - Workflows run with `concurrency` group set
   - Only one staging deployment can run at a time
   - Only one production deployment can run at a time
   - Prevents race conditions

### Rollback Procedures:

If a migration causes issues in production:

1. **Manual Rollback via Supabase**:
   - Go to Supabase Dashboard → SQL Editor
   - Run rollback SQL statements manually
   - Document the issue

2. **Migration Reversal**:
   - Create a new migration file that undoes the changes
   - Push to staging first to test
   - Then push to main with proper approval

3. **Keep Backups**:
   - Supabase automatically backs up daily
   - Request a restore if needed: Support → Request restore point

### Monitoring & Logs:

- **GitHub Actions Logs**:
  - Go to **Actions** → Select workflow → View job logs
  - Look for ✅ or ❌ status icons
  
- **Supabase Logs**:
  - Dashboard → Logs → Postgres Logs
  - Check for migration execution status
  - Look for any errors in SQL execution

---

## Step 8: Create Initial Migrations

### Staging Migration Example:
Create `supabase/migrations/staging/20261005_example.sql`:
```sql
-- Staging-only migration example
CREATE TABLE IF NOT EXISTS staging_test_features (
  id BIGSERIAL PRIMARY KEY,
  feature_name TEXT NOT NULL,
  is_enabled BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE staging_test_features IS 'Test features for staging environment only';
```

### Production Migration Example:
Create `supabase/migrations/prod/20261005_example.sql`:
```sql
-- Production migration example
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS 
  verification_status TEXT DEFAULT 'unverified';

CREATE INDEX IF NOT EXISTS idx_profiles_verification 
ON profiles(verification_status);
```

---

## Step 9: Deployment Checklist

Before pushing migrations:

- [ ] Migration files follow naming convention: `YYYYMMDD_HHmmss_description.sql`
- [ ] Only ONE environment per migration file (staging OR prod)
- [ ] Migration file is idempotent (safe to run multiple times)
- [ ] Tested locally with Supabase CLI:
  ```bash
  supabase link --project-ref <project-id>
  supabase db push --dry-run
  ```
- [ ] Pull request review completed
- [ ] No syntax errors in SQL
- [ ] No breaking schema changes without planning
- [ ] Backup exists (for prod)

---

## Troubleshooting

### Workflow Not Triggering:
- Check that push is to correct branch (staging or main)
- Check that changes include files in trigger paths:
  - `supabase/migrations/staging/**`
  - `supabase/migrations/prod/**`
  - `.github/workflows/*.yml`
- Check **Actions** tab for any errors

### Authentication Failures:
```
Error: Could not authenticate with Supabase
```
- Verify all secrets are correctly set
- Check secret names match exactly (case-sensitive)
- Ensure Service Role Key is from correct project
- Try regenerating Access Token in Supabase

### Migration Fails to Apply:
```
Error: Migration push failed
```
- Check Supabase dashboard for existing schema conflicts
- Verify migration SQL is syntactically correct
- Run `supabase db push --dry-run` locally to test
- Check Postgres logs in Supabase dashboard

### Production Approval Not Showing:
- Check GitHub Environments are set up (Step 4)
- Verify production secrets are added
- Check workflow file has `environment: prod` in deploy job
- Look for any workflow validation errors in Actions tab

---

## Advanced Configuration

### Add Slack Notifications:
Add to workflow after deployment:
```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Deployment ${{ job.status }}",
        "blocks": [...]
      }
```

### Add Database Health Checks:
```bash
- name: Health Check
  run: |
    psql postgres://${{ secrets.DB_USER }}:${{ secrets.DB_PASSWORD }}@host:5432/postgres \
      -c "SELECT version();"
```

### Add Scheduled Migrations:
```yaml
schedule:
  - cron: '0 2 * * *'  # Run at 2 AM UTC daily
```

---

## References

- [Supabase CLI Documentation](https://supabase.com/docs/guides/local-development/cli/getting-started)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Supabase Database Migrations](https://supabase.com/docs/guides/cli/local-development#database-migrations)

---

## Questions or Issues?

Refer to this document or check:
1. GitHub Actions workflow logs (Actions tab)
2. Supabase dashboard logs
3. GitHub Secrets configuration
4. Branch protection rules
