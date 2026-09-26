output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate — a public certificate, not a secret, but still only useful alongside an IAM identity that has an access entry on the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "Issuer host without the https:// prefix — this is the exact string IRSA trust-policy condition keys need (e.g. \"<url>:sub\"), see modules/irsa."
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "node_role_arn" {
  description = "Feed this to the ecr module's pull_principal_arns so nodes can pull images."
  value       = aws_iam_role.node.arn
}
