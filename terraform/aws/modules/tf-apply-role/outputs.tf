output "role_arn" {
  description = "Set as the GitHub Environment variable AWS_TF_APPLY_ROLE_ARN for this environment. An identifier, not a credential."
  value       = aws_iam_role.this.arn
}
