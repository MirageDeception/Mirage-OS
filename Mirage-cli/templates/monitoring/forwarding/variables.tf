variable "hub_event_bus_arn" {
  type        = string
  description = "ARN of the hub's custom EventBus"
}

variable "rule_name" {
  type        = string
  description = "Name of the local EventBridge rule for forwarding"
  default     = "mirage-deception-forwarding"
}
