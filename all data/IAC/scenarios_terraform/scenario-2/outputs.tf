output "role_arn" {
  description = "ARN of the lure payment secrets role"
  value       = aws_iam_role.payment_secrets_readonly_role.arn
}

output "stripe_secret_arn" {
  description = "ARN of the Stripe keys secret"
  value       = aws_secretsmanager_secret.stripe_keys_secret.arn
}

output "braintree_secret_arn" {
  description = "ARN of the Braintree credentials secret"
  value       = aws_secretsmanager_secret.braintree_credentials_secret.arn
}

output "service_accounts_secret_arn" {
  description = "ARN of the service accounts secret"
  value       = aws_secretsmanager_secret.service_accounts_secret.arn
}
