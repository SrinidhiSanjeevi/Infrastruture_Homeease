# ============================================================
# Same bucket as every other AWS environment (see
# environments/dev/backend.tf) — own state KEY so this stack's state
# never collides with dev's or _reference-eks's.
# ============================================================

terraform {
  backend "s3" {
    bucket       = "REPLACE-WITH-BOOTSTRAP-bucket_name-OUTPUT"
    key          = "aws/fargate-dev.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
