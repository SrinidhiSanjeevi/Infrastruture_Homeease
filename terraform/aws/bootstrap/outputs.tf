output "bucket_name" {
  description = "Terraform state bucket name. Paste into every environment's backend.tf."
  value       = aws_s3_bucket.tfstate.id
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}
