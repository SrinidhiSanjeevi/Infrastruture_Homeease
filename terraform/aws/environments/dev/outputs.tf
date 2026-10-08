# These become GitHub repository VARIABLES on the APP repo (app_Homeease)

output "account_id" {
  value = module.ci_oidc.account_id
}

output "ci_role_arn" {
  value = module.ci_oidc.push_role_arn
}

output "ci_read_role_arn" {
  value = module.ci_oidc.read_role_arn
}

output "oidc_provider_arn" {
  description = "Pass this to staging/prod as their oidc_provider_arn variable — they trust the same provider, not a second one."
  value       = module.ci_oidc.oidc_provider_arn
}

output "tf_apply_role_arn" {
  description = "Set as this environment's GitHub Environment (dev) variable AWS_TF_APPLY_ROLE_ARN. Lets the INFRA repo's workflow plan/apply this stack — separate from ci_role_arn, which is only for the APP repo's image pushes."
  value       = aws_iam_role.tf_apply.arn
}

output "registry_url" {
  value = module.ecr.registry_url
}

output "repository_urls" {
  value = module.ecr.repository_urls
}

output "repository_arns" {
  value = module.ecr.repository_arns
}

# Consumed by fargate-dev via `terraform_remote_state`

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "backend_secret_arns" {
  value = module.backend_secrets.secret_arns
}

output "admin_backend_secret_arns" {
  value = module.admin_backend_secrets.secret_arns
}

output "payment_secret_arns" {
  value = module.payment_secrets.secret_arns
}

output "notification_secret_arns" {
  value = module.notification_secrets.secret_arns
}
