output "frontend_url" {
  value = module.alb.frontend_url
}

output "admin_frontend_url" {
  value = module.alb.admin_frontend_url
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "tf_apply_role_arn" {
  description = "Set as this environment's GitHub Environment (fargate-dev) variable AWS_TF_APPLY_ROLE_ARN."
  value       = module.tf_apply_role.role_arn
}
