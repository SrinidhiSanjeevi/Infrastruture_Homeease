output "security_group_id" {
  value = aws_security_group.alb.id
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "admin_frontend_target_group_arn" {
  value = aws_lb_target_group.admin_frontend.arn
}

output "frontend_url" {
  value = "http://${aws_lb.this.dns_name}/"
}

output "admin_frontend_url" {
  value = "http://${aws_lb.this.dns_name}:8081/"
}

output "frontend_https_url" {
  value = var.certificate_arn != null ? "https://${aws_lb.this.dns_name}/" : null
}

output "arn_suffix" {
  description = "Load balancer ARN suffix, used as the LoadBalancer dimension in CloudWatch."
  value       = aws_lb.this.arn_suffix
}

output "frontend_tg_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch TargetGroup dimension)."
  value       = aws_lb_target_group.frontend.arn_suffix
}

output "admin_frontend_tg_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch TargetGroup dimension)."
  value       = aws_lb_target_group.admin_frontend.arn_suffix
}
