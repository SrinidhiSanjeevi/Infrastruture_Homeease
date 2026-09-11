output "secret_arns" {
  description = "Map of secret name suffix -> ARN. Feed this to the irsa module's secret_arns so a workload's IAM role can read exactly these and nothing else."
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}

output "secret_names" {
  value = { for k, v in aws_secretsmanager_secret.this : k => v.name }
}
