# Scenario 17 — SAML Provider Lure: Fake Okta SSO Integration

## Prompt

Create a deception scenario called `scenario-17` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: sso-audit-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► iam:ListSAMLProviders → finds ProdOktaSSO
  │
  ├─► iam:GetSAMLProvider → downloads SAML metadata XML
  │     ├─► Entity ID, SSO URL, certificate
  │     └─► Attribute mappings (email, groups, roles)
  │
  ├─► iam:ListRoles (filtered by SAML trust) → finds roles trusting the provider
  │     └─► prod-okta-admin-role, prod-okta-developer-role
  │
  └─► Attempts to forge SAML assertion or access Okta endpoint → triggers detection
```

### Lure Resources

- **IAM Role (Discovery)**: Named `sso-audit-readonly-role`
  - `iam:ListSAMLProviders`, `iam:GetSAMLProvider`
  - `iam:ListRoles`, `iam:GetRole`
  - Trust: account root principal

- **SAML Provider**: Named `ProdOktaSSO`
  - Fake SAML metadata XML with:
    - Entity ID: `https://acme-corp.okta.com/app/exk1prod2abc3def4`
    - SSO URL: `https://acme-corp.okta.com/app/amazon_aws/exk1prod2abc3def4/sso/saml`
    - Fake X.509 certificate (self-signed, generated during deploy)

- **IAM Role (SAML-trusted 1)**: Named `prod-okta-admin-role`
  - Trust: SAML provider `ProdOktaSSO` with condition on `SAML:aud`
  - Permissions: `AdministratorAccess` (looks scary but can't be assumed without valid SAML)
  - Tags: `SSOProvider=Okta`, `AccessLevel=admin`

- **IAM Role (SAML-trusted 2)**: Named `prod-okta-developer-role`
  - Trust: SAML provider `ProdOktaSSO`
  - Permissions: `PowerUserAccess`
  - Tags: `SSOProvider=Okta`, `AccessLevel=developer`

### Additional Requirements

- [ ] Cost: $0.00/month
- [ ] SAML metadata must be valid XML structure with fake but realistic values
- [ ] Deploy script generates a self-signed cert for the metadata
- [ ] SAML-trusted roles cannot be assumed without a valid SAML assertion
- [ ] Include `deploy.sh`, `README.md`, `fake-data/saml-metadata.xml`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-17/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── saml-metadata.xml
└── README.md
```
