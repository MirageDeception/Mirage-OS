# Scenario 17

**Description**: Deception Scenario 17 - SAML provider lure with fake Okta SSO integration. Two SAML-trusted roles (admin + developer) that cannot be assumed without a valid SAML assertion. Discovery role: sso-audit-readonly-role.

This scenario provisions a deceptive IAM environment mimicking an Okta SAML integration:
1. `sso-audit-readonly-role`: A discovery role allowing attackers to list SAML providers and read the specific roles.
2. `ProdOktaSSO`: An IAM SAML Provider configured with fake/realistic Okta metadata.
3. `prod-okta-admin-role` and `prod-okta-developer-role`: Two SAML-trusted roles that require an assertion from the fake Okta provider to assume, thus triggering a deception trap if attempted.
