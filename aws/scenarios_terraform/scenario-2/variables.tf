variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "role_name" {
  type        = string
  description = "Name for the IAM role"
}

variable "stripe_secret_name" {
  type        = string
  description = "Name for the Stripe secret"
}

variable "braintree_secret_name" {
  type        = string
  description = "Name for the Braintree secret"
}

variable "service_accounts_secret_name" {
  type        = string
  description = "Name for the internal service accounts secret"
}
