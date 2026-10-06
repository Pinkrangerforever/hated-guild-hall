# Setup GitHub Secrets - Step-by-Step

## Quick Reference

This document provides step-by-step instructions for adding all required GitHub Secrets.

## What are GitHub Secrets?

GitHub Secrets are encrypted environment variables that:
- Are only available to GitHub Actions workflows
- Cannot be viewed or modified after creation (only deleted)
- Are automatically redacted in logs
- Are scoped to repository-level or environment-level

## Required Secrets Overview

**Total Secrets to Add: 8**

### Staging Secrets (4)
```
SUPABASE_STAGING_PROJECT_REF
SUPABASE_STAGING_ACCESS_TOKEN
SUPABASE_STAGING_SERVICE_ROLE_KEY
SUPABASE_STAGING_DB_PASSWORD
```

### Production Secrets (4)
```
SUPABASE_PROD_PROJECT_REF
SUPABASE_PROD_ACCESS_TOKEN
SUPABASE_PROD_SERVICE_ROLE_KEY
SUPABASE_PROD_DB_PASSWORD
```

---

## Step-by-Step Instructions

### 1. Go to GitHub Secrets Page

1. Navigate to: https://github.com/Pinkrangerforever/hated-guild-hall/settings/secrets/actions
2. You should see a page titled "Actions → Secrets and variables"

### 2. Add SUPABASE_STAGING_PROJECT_REF

1. Click **"New repository secret"** button
2. **Name:** `SUPABASE_STAGING_PROJECT_REF`
3. **Value:** `jucmmnmnbjrzmjrugggl`
4. Click **"Add secret"**

### 3. Add SUPABASE_STAGING_ACCESS_TOKEN

1. Click **"New repository secret"**
2. **Name:** `SUPABASE_STAGING_ACCESS_TOKEN`
3. **Value:** Generate one of these:

#### Option A: Use Existing Token (if you have one)
- Check `~/.supabase/access-token` on your local machine (if already logged in)

#### Option B: Generate New Token
1. Go to [Supabase Account Settings](https://app.supabase.com/account/tokens)
2. Click **"Generate new token"**
3. **Name:** `github-actions-ci-cd-staging`
4. Copy the token (starts with `sbp_`)
5. **Value:** Paste the token here

4. Click **"Add secret"**

### 4. Add SUPABASE_STAGING_SERVICE_ROLE_KEY

1. Click **"New repository secret"**
2. **Name:** `SUPABASE_STAGING_SERVICE_ROLE_KEY`
3. **Value:** 
   - Go to [Supabase Dashboard](https://app.supabase.com)
   - Click on STAGING project (`jucmmnmnbjrzmjrugggl`)
   - Go to **Settings → API**
   - Scroll down to find **"Project API keys"**
   - Copy the **"service_role"** key (⚠️ NOT the anon key)
   - ⚠️ This is sensitive - keep it secret!
4. Click **"Add secret"**

### 5. Add SUPABASE_STAGING_DB_PASSWORD

1. Click **"New repository secret"**
2. **Name:** `SUPABASE_STAGING_DB_PASSWORD`
3. **Value:** Your STAGING database password
   - Check your local `.env` or `.env.local` file
   - Or retrieve from where you set up Supabase initially
   - Format: `postgresql://postgres:[PASSWORD]@...`
   - Extract just the `[PASSWORD]` part
4. Click **"Add secret"**

### 6. Repeat for Production Secrets

Repeat steps 2-5, but for the PRODUCTION environment:

#### 6a. SUPABASE_PROD_PROJECT_REF
- **Name:** `SUPABASE_PROD_PROJECT_REF`
- **Value:** `dymlprrudprwyctjqqer`

#### 6b. SUPABASE_PROD_ACCESS_TOKEN
- **Name:** `SUPABASE_PROD_ACCESS_TOKEN`
- **Value:** Generate new token at [Supabase Account Settings](https://app.supabase.com/account/tokens)
- **Name it:** `github-actions-ci-cd-prod`

#### 6c. SUPABASE_PROD_SERVICE_ROLE_KEY
- **Name:** `SUPABASE_PROD_SERVICE_ROLE_KEY`
- **Value:** 
  - Go to [Supabase Dashboard](https://app.supabase.com)
  - Click on PRODUCTION project (`dymlprrudprwyctjqqer`)
  - Go to **Settings → API**
  - Copy the **"service_role"** key

#### 6d. SUPABASE_PROD_DB_PASSWORD
- **Name:** `SUPABASE_PROD_DB_PASSWORD`
- **Value:** Your PRODUCTION database password
- ⚠️ Make sure this is the PRODUCTION password, not staging!

### 7. Verify All Secrets Added

After adding all 8 secrets, you should see a list like:

```
✓ SUPABASE_PROD_ACCESS_TOKEN
✓ SUPABASE_PROD_DB_PASSWORD
✓ SUPABASE_PROD_PROJECT_REF
✓ SUPABASE_PROD_SERVICE_ROLE_KEY
✓ SUPABASE_STAGING_ACCESS_TOKEN
✓ SUPABASE_STAGING_DB_PASSWORD
✓ SUPABASE_STAGING_PROJECT_REF
✓ SUPABASE_STAGING_SERVICE_ROLE_KEY
```

---

## Creating GitHub Environments (Optional but Recommended)

GitHub Environments provide additional protection for production deployments.

### Create Staging Environment

1. Go to: https://github.com/Pinkrangerforever/hated-guild-hall/settings/environments
2. Click **"New environment"**
3. **Name:** `staging`
4. Click **"Configure environment"**
5. (Optional) Add environment-specific secrets here if different from repo secrets
6. Click **"Save protection rules"**

### Create Production Environment

1. Click **"New environment"** again
2. **Name:** `prod`
3. Click **"Configure environment"**
4. **⚠️ RECOMMENDED - Enable Protection:**
   - Check: **"Required reviewers"**
   - Add at least 1 reviewer (can be yourself + a team member)
   - Check: **"Deployment branches"**
   - Set to: `main`
5. Click **"Save protection rules"**

This ensures that production deployments require manual approval before running.

---

## Verifying Secrets Are Working

### Method 1: Trigger a Test Deployment

1. Create a test migration file:
```bash
echo "-- Test" > supabase/migrations/staging/20261005_test.sql
git add supabase/migrations/staging/20261005_test.sql
git commit -m "Test: Verify workflow"
git push origin staging
```

2. Go to **Actions** tab on GitHub
3. Click on **"Deploy Staging Migrations"** workflow
4. If secrets are correct, the workflow should:
   - ✅ Pass authentication
   - ✅ List migrations
   - ✅ Apply migrations
   - ✅ Show success message

### Method 2: Check Workflow Logs

If the workflow fails:
1. Click on the failed workflow run
2. Click on the "Apply Staging Migrations" job
3. Expand each step to see detailed logs
4. Common errors:
   - `Invalid authentication` → Check secret values
   - `Project not found` → Check PROJECT_REF is correct
   - `Migration failed` → Check SQL syntax

---

## Troubleshooting

### "Invalid authentication" Error
- Verify secret names are spelled exactly (case-sensitive)
- Check Access Token is not expired (rotate every 90 days)
- Verify Service Role Key is from correct project
- Try regenerating the token

### "Project not found" Error
- Verify PROJECT_REF value is correct:
  - Staging: `jucmmnmnbjrzmjrugggl`
  - Production: `dymlprrudprwyctjqqer`
- Check you're using the correct Supabase project

### "Cannot access secret" Error
- Secret may not be available to this workflow
- Check secret is in the repository (not just environment)
- Verify workflow file uses correct secret reference

### Still Stuck?

1. Check [GitHub Actions Troubleshooting](https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows)
2. Review workflow logs in detail
3. Verify local Supabase CLI works: `supabase link --project-ref jucmmnmnbjrzmjrugggl`
4. Check Supabase dashboard for any issues

---

## Security Best Practices

✅ **DO:**
- Use dedicated tokens for GitHub Actions (not personal tokens)
- Rotate tokens every 90 days
- Use different passwords/tokens for staging vs production
- Enable branch protection on `main`
- Require reviewers for production deployments
- Store backup of tokens in secure location (password manager)
- Monitor Actions runs for suspicious activity

❌ **DON'T:**
- Share secrets with team via Slack/email
- Commit secrets to repository (they'll be leaked)
- Use production passwords in staging
- Forget to rotate tokens
- Skip production approval step
- Store secrets in plain text files
- Share GitHub PATs with others

---

## Token Rotation Reminder

Set a calendar reminder to:
- ✅ Generate new Access Token every 90 days
- ✅ Update GitHub Secrets with new token
- ✅ Delete old token from Supabase

**Suggested dates:**
- Created: October 2026
- Rotate: January 2027
- Rotate: April 2027
- Rotate: July 2027
- Rotate: October 2027

---

## Questions?

Refer to:
- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Supabase CLI Authentication](https://supabase.com/docs/guides/local-development/cli/getting-started)
- Main setup guide: `GITHUB_ACTIONS_SETUP.md`
