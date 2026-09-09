output "push_role_arn" {
  description = "Set this as the GitHub repository VARIABLE AWS_CI_ROLE_ARN. It is an identifier, not a credential — it does not belong in secrets."
  value       = aws_iam_role.push.arn
}

output "read_role_arn" {
  description = "Role ARN for pull_request workflows."
  value       = try(aws_iam_role.read[0].arn, null)
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider. Pass to other stacks as existing_oidc_provider_arn."
  value       = local.oidc_provider_arn
}

output "account_id" {
  description = "AWS account ID — set as the GitHub variable AWS_ACCOUNT_ID."
  value       = data.aws_caller_identity.current.account_id
}
