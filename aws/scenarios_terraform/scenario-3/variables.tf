variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "role_name" { type = string }
variable "param_db" { type = string }
variable "param_gh" { type = string }
variable "param_dd" { type = string }
variable "param_vpn" { type = string }
variable "param_eks" { type = string }
