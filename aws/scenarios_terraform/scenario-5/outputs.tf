

output "ecr_repo_uri" {
  description = "URI of the lure ECR repository"
  value       = aws_ecr_repository.payment_service_repo.repository_url
}

output "ecr_repo_arn" {
  description = "ARN of the lure ECR repository"
  value       = aws_ecr_repository.payment_service_repo.arn
}

output "instance_profile_arn" {
  description = "ARN of the instance profile to attach to scenario-4 bastion"
  value       = aws_iam_instance_profile.bastion_instance_profile.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = aws_iam_instance_profile.bastion_instance_profile.name
}
