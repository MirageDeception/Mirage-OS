variable "event_bus_name" {
  type        = string
  description = "Name of the central deception EventBus"
}

variable "sns_topic_name" {
  type        = string
  description = "Name of the SNS topic for alerts"
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the brain Lambda function"
}

variable "lambda_zip_path" {
  type        = string
  description = "Path to the zipped lambda code"
  default     = "brain.zip"
}
