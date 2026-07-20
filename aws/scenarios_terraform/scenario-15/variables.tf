variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "role_audit" { type = string }
variable "role_admin" { type = string }
variable "role_developer" { type = string }

variable "saml_metadata_document" {
  type        = string
  description = "SAML metadata XML document"
  default     = <<-EOT
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" entityID="http://www.okta.com/dummy">
  <!-- PADDING TO REACH 1000 CHARACTERS FOR AWS IAM SAML PROVIDER LIMIT
       AWS requires SAML provider metadata to be at least 1000 characters.
       This is a dummy SAML document for the Okta honeypot.
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
       xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  -->
  <md:IDPSSODescriptor WantAuthnRequestsSigned="false" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <md:KeyDescriptor use="signing">
      <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:X509Data>
          <ds:X509Certificate>MIIDhzCCAm+gAwIBAgIUV6dF1Ous2eyOk6KxLh/R5I5w6YAwDQYJKoZIhvcNAQELBQAwUzELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVN0YXRlMQ0wCwYDVQQHDARDaXR5MQwwCgYDVQQKDANPcmcxFzAVBgNVBAMMDmR1bW15Lm9rdGEuY29tMB4XDTI2MDcyMDA3MDIxOVoXDTI3MDcyMDA3MDIxOVowUzELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVN0YXRlMQ0wCwYDVQQHDARDaXR5MQwwCgYDVQQKDANPcmcxFzAVBgNVBAMMDmR1bW15Lm9rdGEuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzJfacz+rMtRO3bQmrbRkU/m4Djr0ZNLVPlzPYNdNMVowdXw/6r6Bt+EgqbFmqCIaynm6KKpYTSEul6RBcdeVchoa4VKcRwP09PvcHWlSPfyWCIzN2Hir84L8Tz5jds5aK9MLYq/+DYTgS3HBi20WVAil0Tbb4vCIUiROH4betJGr+2Kvg0QOv4THSjB2sDB535vrm/U1sYJvKgtsQViBkZK3c4JUfYqc+P8kZzdfPRCxjmKqTh643v/TEHHaR48B6J0wmtauSIlZ7UB9xlaZr+G46VbMEX1dDSPP4ggSmNYq4t1VwkTPp8ozZ4AxQ9jyvdHsRcJCqvJVJUlitvR3dwIDAQABo1MwUTAdBgNVHQ4EFgQUviP8O59uyP2yT0XXOCS+7DxcIJMwHwYDVR0jBBgwFoAUviP8O59uyP2yT0XXOCS+7DxcIJMwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAYJpybqbWSaeXB/FtXRmCntp2keTWk8rmO+LGQBdMYtP8AA7PHLaB7DE7n5+m2UI8OLXePN12m16i6aCRreqhg2X2oiSEQXGFi351Dk7mUqTZhaDWtNQPL7vCdXwUxwEflnUdMSAhrkRoPBKA5qvq8I68EygiXqGcAJPtfRpJPp2TD4ffnS4Qvq6iRagiTsCYBXSfqDCtCfwGx/pFDa1jiVp8bgXlqcCMjgwJ9cWB+GHbUzpSOPNmHoNvFDEHGAP8v9SuWzVVfRJvjFUhdM3aRgj5ryIZTQz2TPFSru8U7mBZK5qxLKMM51lUJFE2sVW/xdJeDZXimgK+KlvImuJPsA==</ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
    </md:KeyDescriptor>
    <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://dummy.okta.com/app/dummy/sso/saml"/>
    <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://dummy.okta.com/app/dummy/sso/saml"/>
  </md:IDPSSODescriptor>
</md:EntityDescriptor>
EOT
}
