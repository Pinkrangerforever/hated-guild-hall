# GitHub Actions Workflows

This directory contains automated CI/CD workflows for Supabase database migrations.

## Workflows

### staging.yml
**Automatic deployment to STAGING database**
- Trigger: Push to `staging` branch
- Changes: `supabase/migrations/staging/**`
- Action: Auto-applies migrations (no approval needed)
- Environment: staging (jucmmnmnbjrzmjrugggl)

### prod.yml
**Controlled deployment to PRODUCTION database**
- Trigger: Push to `main` branch
- Changes: `supabase/migrations/prod/**`
- Action: Requires manual approval before applying
- Environment: prod (dymlprrudprwyctjqqer)

## Quick Start

1. **Setup GitHub Secrets:** See `GITHUB_ACTIONS_SETUP.md`
2. **Add Migration Files:**
   - Staging: `supabase/migrations/staging/*.sql`
   - Production: `supabase/migrations/prod/*.sql`
3. **Push to Branch:**
   - Staging: `git push origin staging`
   - Production: `git push origin main`
4. **Monitor:** Check Actions tab for workflow status

## Documentation

- **Setup Guide:** `GITHUB_ACTIONS_SETUP.md`
- **Secrets Setup:** `scripts/setup-github-secrets.md`
- **Migration Reference:** `docs/MIGRATION_WORKFLOW_REFERENCE.md`
- **Verification Script:** `scripts/verify-github-actions-setup.sh`

## Quick Troubleshooting

### Workflow not triggering?
- Verify branch name is correct (`staging` or `main`)
- Check file changes are in migration directories
- View workflow file syntax in GitHub

### Secret errors?
- Verify secrets are in repository settings
- Check secret names match exactly (case-sensitive)
- Regenerate tokens if expired

### Migration failed?
- Check SQL syntax in migration file
- Run `supabase db push --dry-run` locally first
- Review Postgres logs in Supabase dashboard

## Support

For detailed information:
1. Read `GITHUB_ACTIONS_SETUP.md` for complete setup
2. Check `docs/MIGRATION_WORKFLOW_REFERENCE.md` for technical details
3. Run `scripts/verify-github-actions-setup.sh` to validate setup
