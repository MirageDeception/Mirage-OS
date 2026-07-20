variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies and ARNs"
}

variable "role_auth" { type = string }
variable "role_data" { type = string }
variable "role_admin" { type = string }
variable "param_auth" { type = string }
variable "param_data" { type = string }
variable "param_admin" { type = string }
