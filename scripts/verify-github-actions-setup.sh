#!/bin/bash

# GitHub Actions CI/CD Setup Verification Script
# This script verifies that all required components are in place for
# automated Supabase migrations via GitHub Actions

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GitHub Actions CI/CD Setup Verification ===${NC}\n"

# Check 1: Workflow files exist
echo -e "${BLUE}[1/7] Checking workflow files...${NC}"
if [ -f ".github/workflows/staging.yml" ]; then
    echo -e "${GREEN}✓${NC} Staging workflow found"
else
    echo -e "${RED}✗${NC} Staging workflow missing: .github/workflows/staging.yml"
fi

if [ -f ".github/workflows/prod.yml" ]; then
    echo -e "${GREEN}✓${NC} Production workflow found"
else
    echo -e "${RED}✗${NC} Production workflow missing: .github/workflows/prod.yml"
fi
echo ""

# Check 2: Migration directories exist
echo -e "${BLUE}[2/7] Checking migration directories...${NC}"
if [ -d "supabase/migrations/staging" ]; then
    echo -e "${GREEN}✓${NC} Staging migrations directory exists"
    STAGING_COUNT=$(find supabase/migrations/staging -name "*.sql" | wc -l)
    echo "  └─ Contains $STAGING_COUNT migration file(s)"
else
    echo -e "${RED}✗${NC} Staging migrations directory missing: supabase/migrations/staging"
fi

if [ -d "supabase/migrations/prod" ]; then
    echo -e "${GREEN}✓${NC} Production migrations directory exists"
    PROD_COUNT=$(find supabase/migrations/prod -name "*.sql" | wc -l)
    echo "  └─ Contains $PROD_COUNT migration file(s)"
else
    echo -e "${RED}✗${NC} Production migrations directory missing: supabase/migrations/prod"
fi
echo ""

# Check 3: Git branches
echo -e "${BLUE}[3/7] Checking git branches...${NC}"
if git rev-parse --verify staging >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Staging branch exists"
else
    echo -e "${YELLOW}⚠${NC} Staging branch not found (check branch name)"
fi

if git rev-parse --verify main >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Main branch exists"
else
    echo -e "${RED}✗${NC} Main branch not found (workflows require 'main' branch)"
fi
echo ""

# Check 4: Supabase CLI
echo -e "${BLUE}[4/7] Checking Supabase CLI...${NC}"
if command -v supabase &> /dev/null; then
    SUPABASE_VERSION=$(supabase --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} Supabase CLI installed: $SUPABASE_VERSION"
else
    echo -e "${YELLOW}⚠${NC} Supabase CLI not found locally (required for local testing)"
    echo "  Install with: npm install -g supabase"
fi
echo ""

# Check 5: Git configuration
echo -e "${BLUE}[5/7] Checking git configuration...${NC}"
REPO_URL=$(git config --get remote.origin.url)
if [[ $REPO_URL == *"github.com"* ]]; then
    echo -e "${GREEN}✓${NC} GitHub repository detected"
    echo "  └─ URL: $REPO_URL"
else
    echo -e "${RED}✗${NC} Not a GitHub repository: $REPO_URL"
fi

GIT_USER=$(git config --get user.name)
echo -e "${GREEN}✓${NC} Git user: $GIT_USER"
echo ""

# Check 6: Environment setup documentation
echo -e "${BLUE}[6/7] Checking documentation...${NC}"
if [ -f "GITHUB_ACTIONS_SETUP.md" ]; then
    echo -e "${GREEN}✓${NC} Setup documentation found: GITHUB_ACTIONS_SETUP.md"
else
    echo -e "${YELLOW}⚠${NC} Setup documentation missing: GITHUB_ACTIONS_SETUP.md"
fi
echo ""

# Check 7: Secret validation helper
echo -e "${BLUE}[7/7] GitHub Secrets Status${NC}"
echo -e "${YELLOW}⚠${NC} Cannot verify secrets (they're encrypted on GitHub)"
echo "  Required secrets to add:"
echo "  • SUPABASE_STAGING_PROJECT_REF (jucmmnmnbjrzmjrugggl)"
echo "  • SUPABASE_STAGING_ACCESS_TOKEN"
echo "  • SUPABASE_STAGING_SERVICE_ROLE_KEY"
echo "  • SUPABASE_STAGING_DB_PASSWORD"
echo "  • SUPABASE_PROD_PROJECT_REF (dymlprrudprwyctjqqer)"
echo "  • SUPABASE_PROD_ACCESS_TOKEN"
echo "  • SUPABASE_PROD_SERVICE_ROLE_KEY"
echo "  • SUPABASE_PROD_DB_PASSWORD"
echo ""
echo "  Add at: GitHub → Settings → Secrets and variables → Actions"
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo "Next steps:"
echo "1. Verify all checkmarks (✓) above"
echo "2. Add GitHub Secrets: https://github.com/Pinkrangerforever/hated-guild-hall/settings/secrets/actions"
echo "3. Set up GitHub Environments: https://github.com/Pinkrangerforever/hated-guild-hall/settings/environments"
echo "4. Test with a test migration push"
echo ""
echo "For detailed setup instructions, see: GITHUB_ACTIONS_SETUP.md"
