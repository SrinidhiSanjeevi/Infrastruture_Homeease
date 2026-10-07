# Same bucket as every other AWS environment (see environments/dev/backend.tf) - own state KEY so this
# stack's state never collides with dev's or fargate-dev's. use_lockfile = native S3 locking, so two
# concurrent applies cannot both write.
terraform {
  backend "s3" {
    bucket       = "tfstate-homeease-aws-ukrvn9"
    key          = "aws/eks-dev.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
