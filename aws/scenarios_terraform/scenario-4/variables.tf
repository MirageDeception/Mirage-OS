variable "account_id" {
  type        = string
  description = "AWS Account ID for trust and bucket policies"
}

variable "key_pair_name" {
  type        = string
  default     = "prod-bastion-keypair"
  description = "Name of the EC2 key pair (created by deploy script)"
}

variable "vpc_id" {
  type        = string
  description = "VPC to deploy the bastion instance into"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet within the selected VPC"
}

variable "allowed_ssh_cidr" {
  type        = string
  default     = "165.225.0.0/24"
  description = "CIDR range allowed to SSH into the bastion"
}

variable "ami_id" {
  type        = string
  default     = "ami-072cdf002809ade8c"
  description = "EC2 AMI ID for the bastion instance. Default is an org-approved AMI. Override if deploying in a different region or if the default is unavailable."
}
