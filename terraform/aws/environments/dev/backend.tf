# ============================================================
# Apply terraform/aws/bootstrap FIRST, then paste its bucket_name
# output below. Do not run this environment against local state —
# see the bootstrap stack's header comment for why.
# ============================================================

terraform {
  backend "s3" {
    bucket       = "REPLACE-WITH-BOOTSTRAP-bucket_name-OUTPUT"
    key          = "aws/dev.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
