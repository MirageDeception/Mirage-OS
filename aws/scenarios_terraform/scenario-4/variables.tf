variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and bucket policies"
}

variable "role_name" { type = string }
variable "bucket_name" { type = string }

variable "allowed_ssh_cidr" {
  type        = string
  default     = "165.225.0.0/24"
  description = "CIDR range allowed to SSH into the bastion"
}
