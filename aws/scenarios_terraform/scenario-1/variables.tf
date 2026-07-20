variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_readonly" { type = string }
variable "bucket_name" { type = string }
