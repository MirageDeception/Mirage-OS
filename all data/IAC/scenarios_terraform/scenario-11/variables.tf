variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "include_customer_profiles" {
  type        = bool
  default     = true
  description = "Include customer profiles table (fake PII)"
}

variable "include_active_sessions" {
  type        = bool
  default     = true
  description = "Include active sessions table (fake JWTs)"
}
