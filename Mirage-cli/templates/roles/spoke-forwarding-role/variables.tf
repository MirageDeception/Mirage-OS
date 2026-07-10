variable "hub_account_id" {
  description = "AWS account ID of the hub account."
  type        = string
}

variable "hub_region" {
  description = "AWS region where the hub EventBus lives."
  type        = string
}

variable "hub_event_bus_name" {
  description = "Name of the hub EventBus (e.g. 'deception-global-event-bus')."
  type        = string
  default     = "deception-global-event-bus"
}

variable "spoke_alias" {
  description = "Human-readable alias for this spoke."
  type        = string
}

variable "forwarding_role_name" {
  description = "Name for the EventBridge forwarding IAM role."
  type        = string
  default     = "mirage-forwarding-role"
}
