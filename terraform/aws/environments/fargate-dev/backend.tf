# Same bucket as every other AWS environment (see environments/dev/backend.tf)

terraform {
  backend "s3" {
    bucket       = "tfstate-homeease-aws-ukrvn9"
    key          = "aws/fargate-dev.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
