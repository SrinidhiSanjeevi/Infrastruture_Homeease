output "repository_urls" {
  description = "Map of service name -> full repository URL."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of service name -> repository ARN. Feed this to the ci-oidc module so push permissions are scoped to exactly these repositories."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_url" {
  description = "Registry host, e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com — set this as the AWS_ACCOUNT_ID/AWS_REGION pair in GitHub variables."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}
