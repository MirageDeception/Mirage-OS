variable "account_id" {
  type        = string
  description = "AWS Account ID for ARNs"
}

variable "role_inventory" { type = string }
variable "role_backup" { type = string }
variable "param_registry" { type = string }
