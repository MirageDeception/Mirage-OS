output "role_arn" {
  description = "ARN of the lure S3 data access role"
  value       = aws_iam_role.s3_data_access_role.arn
}

output "bucket_name" {
  description = "Name of the lure Terraform state bucket"
  value       = aws_s3_bucket.terraform_state_bucket.id
}

output "bucket_arn" {
  description = "ARN of the lure Terraform state bucket"
  value       = aws_s3_bucket.terraform_state_bucket.arn
}
