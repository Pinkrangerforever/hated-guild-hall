# CI/CD Safety Checklist

Use this checklist to verify your GitHub Actions CI/CD setup is production-ready.

## Pre-Deployment Checklist

### GitHub Configuration
- [ ] All 8 GitHub Secrets added and verified
  - [ ] SUPABASE_STAGING_PROJECT_REF
  - [ ] SUPABASE_STAGING_ACCESS_TOKEN
  - [ ] SUPABASE_STAGING_SERVICE_ROLE_KEY
  - [ ] SUPABASE_STAGING_DB_PASSWORD
  - [ ] SUPABASE_PROD_PROJECT_REF
  - [ ] SUPABASE_PROD_ACCESS_TOKEN
  - [ ] SUPABASE_PROD_SERVICE_ROLE_KEY
  - [ ] SUPABASE_PROD_DB_PASSWORD
- [ ] GitHub Environments created (`staging` and `prod`)
- [ ] Production environment requires reviewer approval
- [ ] Branch protection rules set on `main` branch
  - [ ] Require pull request reviews (min 1)
  - [ ] Require status checks to pass
  - [ ] Dismiss stale reviews

### Workflow Files
- [ ] `.github/workflows/staging.yml` exists and valid YAML
- [ ] `.github/workflows/prod.yml` exists and valid YAML
- [ ] Both workflows configured for correct branches
  - [ ] Staging triggers on: `staging` branch
  - [ ] Production triggers on: `main` branch
- [ ] Trigger paths are correct
  - [ ] Staging watches: `supabase/migrations/staging/**`
  - [ ] Production watches: `supabase/migrations/prod/**`

### Directory Structure
- [ ] `supabase/migrations/staging/` exists
- [ ] `supabase/migrations/prod/` exists
- [ ] Directory structure is correct (no extra nesting)

### Documentation
- [ ] `GITHUB_ACTIONS_SETUP.md` reviewed
- [ ] `scripts/setup-github-secrets.md` completed
- [ ] `docs/MIGRATION_WORKFLOW_REFERENCE.md` bookmarked
- [ ] Team has read setup documentation

### Local Testing
- [ ] Supabase CLI installed: `npm install -g supabase`
- [ ] Can login to Supabase: `supabase login`
- [ ] Can link to staging project: `supabase link --project-ref jucmmnmnbjrzmjrugggl`
- [ ] Can link to prod project: `supabase link --project-ref dymlprrudprwyctjqqer`
- [ ] Dry-run works: `supabase db push --dry-run`

### Staging Deployment Test
- [ ] Created test migration in `supabase/migrations/staging/20261005_test.sql`
- [ ] Committed and pushed to `staging` branch
- [ ] Workflow executed successfully
  - [ ] Found migration file
  - [ ] Applied to STAGING database
  - [ ] Verified success
- [ ] Verified in Supabase dashboard:
  - [ ] Opened STAGING project
  - [ ] Checked SQL Editor → Migrations
  - [ ] Confirmed test migration appears

### Production Deployment Test
- [ ] Created test migration in `supabase/migrations/prod/20261005_test.sql`
- [ ] Committed and pushed to `main` branch
- [ ] Workflow triggered and waited for approval
  - [ ] "Review pending" status appeared
  - [ ] Clicked approval button
  - [ ] Selected `prod` environment
  - [ ] Clicked "Approve and deploy"
- [ ] Deployment completed successfully
- [ ] Verified in Supabase dashboard:
  - [ ] Opened PRODUCTION project
  - [ ] Checked SQL Editor → Migrations
  - [ ] Confirmed test migration appears

### Rollback Procedure
- [ ] Understand rollback process:
  - [ ] Manual SQL rollback via Supabase dashboard
  - [ ] Migration reversal via new migration file
  - [ ] Database restore (if critical)
- [ ] Documented rollback SQL for each migration
- [ ] Backup procedure established
  - [ ] Know how to request restore point from Supabase
  - [ ] Backup location documented

### Monitoring Setup
- [ ] Know how to check GitHub Actions logs
- [ ] Know how to check Supabase database logs
- [ ] Set up Slack notifications (optional)
- [ ] Team has access to monitoring tools

### Team Communication
- [ ] Team understands the process:
  - [ ] Staging: Push → Auto-deploy
  - [ ] Production: Push → Manual approval → Deploy
- [ ] Team knows branch names:
  - [ ] `staging` for staging deployments
  - [ ] `main` for production deployments
- [ ] Team trained on migration file format: `YYYYMMDD_HHMMSS_description.sql`
- [ ] Escalation contacts identified (who approves prod?)

### Safety Measures
- [ ] Concurrency control enabled (only 1 migration at a time)
- [ ] Never store secrets in code or `.env` files
- [ ] All sensitive values in GitHub Secrets only
- [ ] Secrets not visible in workflow logs
- [ ] No hardcoded passwords or tokens anywhere

### Documentation
- [ ] Created documentation for your team:
  - [ ] How to create migrations
  - [ ] How to deploy to staging
  - [ ] How to deploy to production
  - [ ] What to do if something breaks
- [ ] Checklist saved for future reference
- [ ] Setup guide bookmarked

## Pre-Production Migration Checklist

Before pushing any REAL migration to production, verify:

### Migration Code Quality
- [ ] SQL syntax validated (tested locally)
- [ ] Ran `supabase db push --dry-run` successfully
- [ ] No syntax errors or warnings
- [ ] Migration is idempotent (safe to run twice)
  - [ ] Uses `CREATE TABLE IF NOT EXISTS`
  - [ ] Uses `ADD COLUMN IF NOT EXISTS`
  - [ ] No data loss possible
- [ ] Comments added explaining what changed and why
- [ ] Index names are descriptive
- [ ] Constraint names are descriptive

### Data Integrity
- [ ] No breaking schema changes without migration plan
- [ ] Rollback procedure documented
- [ ] Data migration logic verified (if needed)
- [ ] Large table operations done carefully
  - [ ] Not locking tables for too long
  - [ ] Using `NOT VALID` for constraints initially
- [ ] No data loss possible
- [ ] Backup exists (Supabase automatic daily)

### Approval Process
- [ ] Migration reviewed by at least 1 other developer
- [ ] Code review checklist completed
- [ ] Security review passed (if applicable)
- [ ] DBA approval (if applicable)
- [ ] Product team notified (if applicable)

### Deployment Planning
- [ ] Scheduled for low-traffic time (if large migration)
- [ ] Deployment window communicated to team
- [ ] Monitoring plan in place
- [ ] On-call person identified
- [ ] Rollback plan documented and tested

### Post-Deployment Verification
- [ ] Verify migration applied successfully
  - [ ] Check Supabase Migrations tab
  - [ ] Run test query: `SELECT * FROM [table_name] LIMIT 1;`
- [ ] Monitor application for errors
- [ ] Check database performance metrics
- [ ] No unexpected errors in logs
- [ ] All related functionality working

## Ongoing Maintenance

### Regular Tasks
- [ ] Review migrations weekly
- [ ] Check workflow logs for failures
- [ ] Monitor database size and performance
- [ ] Rotate access tokens every 90 days
- [ ] Update documentation as needed

### Monthly Review
- [ ] Verify all secrets still work
- [ ] Check for any migration failures
- [ ] Review access logs
- [ ] Update team training if needed

### Backup & Recovery
- [ ] Verify Supabase daily backups are active
- [ ] Test restore procedure (at least annually)
- [ ] Know how to request restore point
- [ ] Emergency contact list updated

## Red Flags 🚨

Stop and investigate if:
- ❌ Workflow failed but you didn't notice
- ❌ Database in unexpected state
- ❌ Secrets not being recognized
- ❌ Wrong database version applied
- ❌ Data loss or corruption
- ❌ Performance degradation after migration
- ❌ Unintended schema changes
- ❌ Can't connect to database
- ❌ Staging and prod databases are identical (they shouldn't be)
- ❌ Approval was skipped somehow

## Sign-Off

When ready for production deployment, obtain approval:

```
Deployment Setup Review

Project: hated-guild-hall
Date: _______________

Reviewed by:
- Setup Lead: _________________________ 
- Security Review: ____________________
- Infrastructure: _____________________

All checklist items completed: [ ] Yes [ ] No

Approved for production deployment: [ ] Yes [ ] No

Notes:
_________________________________________
_________________________________________
_________________________________________

Signatures:
_________________________________________
_________________________________________
```

## Contact & Escalation

**Setup Questions:**
1. Check documentation files
2. Run verification script: `scripts/verify-github-actions-setup.sh`
3. Review GitHub Actions logs

**Deployment Issues:**
1. Check Supabase logs (Dashboard → Logs)
2. Review workflow logs (GitHub Actions tab)
3. Check database connection

**Emergency Procedures:**
- **Database Down:** Contact Supabase support
- **Migration Failed:** Roll back via reverse migration or restore
- **Secrets Compromised:** Rotate immediately (Actions → Secrets)
- **Unexpected Behavior:** Check application logs and database state

## Resources

- Setup Guide: `GITHUB_ACTIONS_SETUP.md`
- Secret Configuration: `scripts/setup-github-secrets.md`
- Technical Reference: `docs/MIGRATION_WORKFLOW_REFERENCE.md`
- Verification Script: `scripts/verify-github-actions-setup.sh`
- Quick Start: `QUICKSTART_CI_CD.md`

---

**Version:** 1.0  
**Last Updated:** 2026-10-05  
**Status:** Ready for deployment
