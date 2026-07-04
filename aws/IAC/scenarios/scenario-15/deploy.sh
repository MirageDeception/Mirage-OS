#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 17 (SAML Provider - Fake Okta SSO)
#
# This script:
#   1. Generates a self-signed X.509 certificate for the SAML metadata
#   2. Builds a realistic SAML metadata XML document
#   3. Deploys the CloudFormation stack (SAML provider + 3 IAM roles)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - openssl installed (for certificate generation)
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and SAML providers
#
set -euo pipefail

# ---------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-17"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
METADATA_FILE="fake-data/saml-metadata.xml"
CERT_DIR="/tmp/scenario17-cert"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Generate self-signed certificate for SAML metadata
# ---------------------------------------------------------------
info "Generating self-signed X.509 certificate for SAML metadata..."
mkdir -p "${CERT_DIR}"
mkdir -p fake-data

openssl req -x509 -newkey rsa:2048 \
  -keyout "${CERT_DIR}/saml-key.pem" \
  -out "${CERT_DIR}/saml-cert.pem" \
  -days 3650 \
  -nodes \
  -subj "/C=US/ST=California/L=San Francisco/O=Acme Corp/OU=IT/CN=acme-corp.okta.com" \
  2>/dev/null

# Extract the certificate body (strip header/footer, join lines)
CERT_BODY=$(sed '/-----/d' "${CERT_DIR}/saml-cert.pem" | tr -d '\n')
ok "Certificate generated"

# ---------------------------------------------------------------
# Build SAML metadata XML
# ---------------------------------------------------------------
info "Building SAML metadata XML..."

cat > "${METADATA_FILE}" <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
                     entityID="http://www.okta.com/exk1prod2abc3def4"
                     validUntil="2029-12-31T23:59:59Z">
  <md:IDPSSODescriptor WantAuthnRequestsSigned="false"
                        protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <md:KeyDescriptor use="signing">
      <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:X509Data>
          <ds:X509Certificate>${CERT_BODY}</ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
    </md:KeyDescriptor>
    <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
    <md:NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:unspecified</md:NameIDFormat>
    <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
                            Location="https://acme-corp.okta.com/app/amazon_aws/exk1prod2abc3def4/sso/saml"/>
    <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
                            Location="https://acme-corp.okta.com/app/amazon_aws/exk1prod2abc3def4/sso/saml"/>
  </md:IDPSSODescriptor>
  <md:Organization>
    <md:OrganizationName xml:lang="en">Acme Corp</md:OrganizationName>
    <md:OrganizationDisplayName xml:lang="en">Acme Corp</md:OrganizationDisplayName>
    <md:OrganizationURL xml:lang="en">https://www.acme-corp.com</md:OrganizationURL>
  </md:Organization>
  <md:ContactPerson contactType="technical">
    <md:GivenName>Platform Engineering</md:GivenName>
    <md:EmailAddress>platform-eng@acme-corp.com</md:EmailAddress>
  </md:ContactPerson>
</md:EntityDescriptor>
XMLEOF

ok "SAML metadata written to ${METADATA_FILE}"

# ---------------------------------------------------------------
# Read metadata for CloudFormation parameter
# ---------------------------------------------------------------
SAML_METADATA=$(cat "${METADATA_FILE}")

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
info "Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
    AccountId="${ACCOUNT_ID}" \
    SAMLMetadataDocument="${SAML_METADATA}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Wait for stack to stabilize
# ---------------------------------------------------------------
info "Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# ---------------------------------------------------------------
# Verify SAML provider
# ---------------------------------------------------------------
info "Verifying SAML provider..."
PROVIDER_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='SAMLProviderArn'].OutputValue" \
  --output text)
ok "SAML Provider ARN: ${PROVIDER_ARN}"

# ---------------------------------------------------------------
# Clean up temporary certificate files
# ---------------------------------------------------------------
info "Cleaning up temporary certificate files..."
rm -rf "${CERT_DIR}"
ok "Temp files removed"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 17 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack         : ${STACK_NAME}"
echo "  Region        : ${REGION}"
echo "  SAML Provider : ProdOktaSSO"
echo "  Roles         :"
echo "    - sso-audit-readonly-role (discovery)"
echo "    - prod-okta-admin-role (SAML-trusted, AdministratorAccess)"
echo "    - prod-okta-developer-role (SAML-trusted, PowerUserAccess)"
echo "  Metadata      : ${METADATA_FILE}"
echo -e "${GREEN}=============================================${NC}"
echo ""
warn "SAML-trusted roles cannot be assumed without a valid SAML assertion."
warn "The self-signed certificate is embedded in the metadata XML."
echo ""
ok "Done. All resources are live."
