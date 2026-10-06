output "app_url" {
  value = "https://${aws_cloudfront_distribution.this["app"].domain_name}/"
}

output "admin_url" {
  value = "https://${aws_cloudfront_distribution.this["admin"].domain_name}/"
}
