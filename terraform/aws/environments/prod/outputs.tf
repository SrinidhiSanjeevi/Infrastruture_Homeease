output "tf_apply_role_arn" {
  description = "Set as the GitHub Environment (prod) variable AWS_TF_APPLY_ROLE_ARN."
  value       = module.tf_apply_role.role_arn
}
