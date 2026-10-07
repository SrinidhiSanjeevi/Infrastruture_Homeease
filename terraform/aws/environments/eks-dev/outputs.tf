output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "irsa_role_arns" {
  description = "Must match irsa.roleArn in gitops_homeease/charts/*/values-aws-dev.yaml."
  value = {
    app          = module.irsa_app.role_arn
    payment      = module.irsa_payment.role_arn
    notification = module.irsa_notification.role_arn
  }
}

output "tf_apply_role_arn" {
  description = "Set as the infra repo's Actions variable AWS_TF_APPLY_ROLE_ARN so aws-eks-apply.yml can assume it."
  value       = module.tf_apply_role.role_arn
}

output "app_url" {
  description = "Customer site (null until enable_cloudfront = true)."
  value       = var.enable_cloudfront ? module.cloudfront[0].app_url : null
}

output "admin_url" {
  description = "Admin console (null until enable_cloudfront = true)."
  value       = var.enable_cloudfront ? module.cloudfront[0].admin_url : null
}

output "fargate_teardown_role_arn" {
  description = "Set as the infra repo's Actions variable AWS_FARGATE_TEARDOWN_ROLE_ARN (null unless create_fargate_teardown_role = true)."
  value       = var.create_fargate_teardown_role ? aws_iam_role.fargate_teardown[0].arn : null
}
