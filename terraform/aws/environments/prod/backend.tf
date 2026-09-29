terraform {
  backend "s3" {
    bucket       = "tfstate-homeease-aws-ukrvn9"
    key          = "aws/prod.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
