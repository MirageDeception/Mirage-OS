variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "include_s3" {
  type    = bool
  default = true
}

variable "include_secrets_manager" {
  type    = bool
  default = true
}

variable "include_ssm" {
  type    = bool
  default = true
}

variable "role_ops" { type = string }
variable "role_exec" { type = string }
variable "lambda_name" { type = string }
variable "bucket_name" { type = string }
variable "secret_api" { type = string }
variable "param_config" { type = string }
