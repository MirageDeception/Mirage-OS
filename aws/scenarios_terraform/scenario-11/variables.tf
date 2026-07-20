variable "account_id" {
  type        = string
  description = "AWS Account ID for trust policies"
}

variable "role_readonly" { type = string }
variable "queue_dlq" { type = string }
variable "queue_main" { type = string }
