variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "include_customer_profiles" {
  type    = bool
  default = true
}

variable "include_active_sessions" {
  type    = bool
  default = true
}

variable "role_readonly" { type = string }
variable "table_profiles" { type = string }
variable "table_sessions" { type = string }
