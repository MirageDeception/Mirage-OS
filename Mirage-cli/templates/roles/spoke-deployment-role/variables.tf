variable "hub_account_id" {
  description = "AWS account ID of the hub (management) account that will assume this role."
  type        = string
}

variable "spoke_account_id" {
  description = "AWS account ID of this spoke (target) account."
  type        = string
}

variable "spoke_alias" {
  description = "Human-readable alias for this spoke (e.g. 'prod', 'dev')."
  type        = string
}

variable "deployment_role_name" {
  description = "Name for the deployment IAM role."
  type        = string
  default     = "mirage-deployment-role"
}

variable "external_id" {
  description = "ExternalId for the AssumeRole trust policy (prevents confused deputy attacks)."
  type        = string
  # Format: mirage-deployment-<spoke_alias>
}
