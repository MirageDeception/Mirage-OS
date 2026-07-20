variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and resource policies"
}

variable "link_to_scenario_6" {
  type        = bool
  default     = false
  description = "If true, adds permissions to Scenario 6's existing role and function"
}

variable "scenario_6_discovery_role_name" {
  type        = string
  default     = ""
  description = "Name of the scenario 6 discovery role (required if link_to_scenario_6 is true)"
}

variable "scenario_6_function_arn" {
  type        = string
  default     = ""
  description = "ARN of the scenario 6 lambda function (required if link_to_scenario_6 is true)"
}

variable "role_discovery" { type = string }
variable "role_exec" { type = string }
variable "lambda_name" { type = string }
