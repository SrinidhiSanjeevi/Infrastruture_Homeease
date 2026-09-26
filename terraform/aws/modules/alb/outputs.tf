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
