variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_name" { type = string }
variable "param_endpoint" { type = string }
variable "param_secrets" { type = string }
variable "stack_name" {
  type    = string
  default = "prod-core-infra-stack"
}
