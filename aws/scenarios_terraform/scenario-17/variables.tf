variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_ops" { type = string }
variable "role_exec" { type = string }
variable "lambda_name" { type = string }
variable "table_name" { type = string }
