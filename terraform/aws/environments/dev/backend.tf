# Apply terraform/aws/bootstrap FIRST, then paste its bucket_name output below.

terraform {
  backend "s3" {
    bucket       = "tfstate-homeease-aws-ukrvn9"
    key          = "aws/dev.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
