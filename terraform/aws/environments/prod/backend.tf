terraform {
  backend "s3" {
    bucket       = "REPLACE-WITH-BOOTSTRAP-bucket_name-OUTPUT"
    key          = "aws/prod.terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
