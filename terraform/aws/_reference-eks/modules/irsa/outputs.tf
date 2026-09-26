output "role_arn" {
  description = "Set as the eks.amazonaws.com/role-arn annotation on the target ServiceAccount — see apps/payment-service/overlays/aws/dev/kustomization.yaml in gitops_homeease."
  value       = aws_iam_role.this.arn
}
