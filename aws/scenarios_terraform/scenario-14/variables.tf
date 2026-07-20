variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_readonly" { type = string }
variable "kms_alias" { type = string }
