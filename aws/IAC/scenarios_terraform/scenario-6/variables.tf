variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "include_s3" {
  type        = bool
  default     = true
  description = "Include S3 bucket with fake pipeline artifacts"
}

variable "include_secrets_manager" {
  type        = bool
  default     = false
  description = "Include Secrets Manager secret ($0.40/mo)"
}

variable "include_ssm" {
  type        = bool
  default     = true
  description = "Include SSM parameter with fake config"
}
