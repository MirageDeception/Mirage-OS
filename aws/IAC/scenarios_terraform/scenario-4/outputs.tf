output "role_arn" {
  description = "ARN of the lure devops S3 deploy role"
  value       = aws_iam_role.devops_s3_deploy_role.arn
}

output "bucket_name" {
  description = "Name of the lure deploy keys bucket"
  value       = aws_s3_bucket.deploy_keys_bucket.id
}

output "instance_id" {
  description = "EC2 instance ID of the lure bastion (deployed stopped)"
  value       = aws_instance.bastion_instance.id
}

output "security_group_id" {
  description = "Security group ID for the lure bastion"
  value       = aws_security_group.bastion_security_group.id
}
