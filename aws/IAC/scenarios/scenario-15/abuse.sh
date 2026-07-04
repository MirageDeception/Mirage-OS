#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 17 (SAML Provider Lure)
#
# This script walks through the attack chain step by step with colored output.
# It assumes the caller has valid AWS credentials for any identity in the account.
#
# Usage:
#   chmod +x abuse.sh
#   ./abuse.sh
#
set -euo pipefail

# ---------------------------------------------------------------
# Colors and helpers
# ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }
info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
attack() { echo -e "  ${RED}[ATTACK]${NC} $1"; }

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 17 — ABUSE CHAIN"
echo "  SAML Provider Lure (Fake Okta SSO)"
echo "============================================="
echo -e "${NC}"

# ---------------------------------------------------------------
step "1" "Resolving account identity"
# ---------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CALLER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
info "Account ID: ${ACCOUNT_ID}"
info "Caller ARN: ${CALLER_ARN}"

# ---------------------------------------------------------------
step "2" "Assuming discovery role: sso-audit-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/sso-audit-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Listing SAML providers (iam:ListSAMLProviders)"
# ---------------------------------------------------------------
attack "iam:ListSAMLProviders"
aws iam list-saml-providers \
  --query "SAMLProviderList[].{Arn: Arn, ValidUntil: ValidUntil, CreateDate: CreateDate}" \
  --output table

PROVIDER_ARN=$(aws iam list-saml-providers \
  --query "SAMLProviderList[?contains(Arn, 'ProdOktaSSO')].Arn" \
  --output text)
info "Target SAML provider: ${PROVIDER_ARN}"

# ---------------------------------------------------------------
step "4" "Getting SAML provider metadata (iam:GetSAMLProvider)"
# ---------------------------------------------------------------
attack "iam:GetSAMLProvider → ${PROVIDER_ARN}"
METADATA=$(aws iam get-saml-provider \
  --saml-provider-arn "${PROVIDER_ARN}" \
  --query "SAMLMetadataDocument" \
  --output text)

info "SAML metadata retrieved. Extracting key details..."
echo ""
echo -e "  ${YELLOW}Entity ID:${NC}"
echo "${METADATA}" | grep -oP 'entityID="[^"]*"' | head -1 || true
echo ""
echo -e "  ${YELLOW}SSO URL:${NC}"
echo "${METADATA}" | grep -oP 'Location="[^"]*"' | head -1 || true
echo ""
echo -e "  ${YELLOW}Organization:${NC}"
echo "${METADATA}" | grep -oP '<md:OrganizationName[^>]*>[^<]*</md:OrganizationName>' | head -1 || true

# Save metadata for offline analysis
echo "${METADATA}" > /tmp/scenario17-saml-metadata.xml
info "Full metadata saved to /tmp/scenario17-saml-metadata.xml"

# ---------------------------------------------------------------
step "5" "Listing IAM roles with SAML trust (iam:ListRoles)"
# ---------------------------------------------------------------
attack "iam:ListRoles (filtering for SAML-trusted roles)"
aws iam list-roles \
  --query "Roles[?contains(to_string(AssumeRolePolicyDocument), 'SAML')].{RoleName: RoleName, Arn: Arn, Description: Description}" \
  --output table

# ---------------------------------------------------------------
step "6" "Inspecting SAML-trusted roles (iam:GetRole)"
# ---------------------------------------------------------------
for SAML_ROLE in "prod-okta-admin-role" "prod-okta-developer-role"; do
  echo ""
  attack "iam:GetRole → ${SAML_ROLE}"
  aws iam get-role \
    --role-name "${SAML_ROLE}" \
    --query "Role.{RoleName: RoleName, Description: Description, MaxSession: MaxSessionDuration, Tags: Tags}" \
    --output json
done

# ---------------------------------------------------------------
step "7" "Attempting to assume SAML-trusted role (expect DENIED)"
# ---------------------------------------------------------------
warn "Attempting sts:AssumeRole on prod-okta-admin-role (no SAML assertion)..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/prod-okta-admin-role"
attack "sts:AssumeRole → ${ADMIN_ROLE_ARN}"

if aws sts assume-role \
  --role-arn "${ADMIN_ROLE_ARN}" \
  --role-session-name "saml-bypass-attempt" \
  --output json 2>/tmp/scenario17-assume-error; then
  warn "AssumeRole succeeded unexpectedly!"
else
  info "AssumeRole DENIED as expected (requires SAML assertion)"
  echo ""
  echo -e "  ${YELLOW}Error:${NC}"
  cat /tmp/scenario17-assume-error | head -3
  rm -f /tmp/scenario17-assume-error
fi

# ---------------------------------------------------------------
step "8" "Summary of extracted intelligence"
# ---------------------------------------------------------------
echo ""
warn "The following SSO infrastructure was discovered:"
echo ""
echo "  • SAML Provider: ProdOktaSSO"
echo "  • Identity Provider: Okta (acme-corp.okta.com)"
echo "  • Entity ID: http://www.okta.com/exk1prod2abc3def4"
echo "  • SSO URL: https://acme-corp.okta.com/app/amazon_aws/exk1prod2abc3def4/sso/saml"
echo "  • Admin Role: prod-okta-admin-role (AdministratorAccess)"
echo "  • Developer Role: prod-okta-developer-role (PowerUserAccess)"
echo ""
warn "SAML-trusted roles cannot be assumed without a valid SAML assertion."
warn "The Okta endpoint and entity ID are breadcrumbs for further recon."

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "9" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
rm -f /tmp/scenario17-saml-metadata.xml
info "Session credentials and temp files cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on sso-audit-readonly-role"
echo "  • CloudTrail: ListSAMLProviders"
echo "  • CloudTrail: GetSAMLProvider on ProdOktaSSO"
echo "  • CloudTrail: ListRoles"
echo "  • CloudTrail: GetRole on prod-okta-admin-role"
echo "  • CloudTrail: GetRole on prod-okta-developer-role"
echo "  • CloudTrail: AssumeRole DENIED on prod-okta-admin-role"
echo ""
