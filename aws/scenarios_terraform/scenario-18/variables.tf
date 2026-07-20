variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_name" { type = string }
variable "param_primary" { type = string }
variable "param_replica" { type = string }
variable "param_backup" { type = string }
variable "param_encryption" { type = string }
variable "param_monitoring" { type = string }
