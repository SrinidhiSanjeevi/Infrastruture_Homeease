# ============================================================
# AWS TERRAFORM STATE BOOTSTRAP
#
# Mirrors terraform/azure/bootstrap: a small, one-time, LOCAL-state
# stack that creates the remote backend every other AWS stack in this
# repo depends on. Apply this once, by hand, before anything in
# terraform/aws/environments/*.
#
# Do not skip this and let dev/staging/prod default to local state —
# that is finding #5 from ANALYSIS.md happening again, this time on
# AWS. A CI runner's local state is destroyed with the workspace at
# the end of the job; the next run has no record of what exists.
#
# S3 native locking (`use_lockfile` on the backend block, Terraform
# >= 1.10) replaces the DynamoDB lock table used in older setups.
# No lock table to create, manage or pay for.
# ============================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "local" {
    path = "bootstrap.tfstate"
  }
}

provider "aws" {
  region = var.region
}

# ============================================================
# STATE BUCKET
# ============================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"

  # Mirrors the Azure bootstrap's prevent_destroy on the state
  # storage account. Losing this bucket loses every environment's
  # state at once.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    component = "terraform-state"
  })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Defence in depth even though every writer here uses the AWS
# provider's own SSE — belt-and-braces for a bucket holding every
# environment's Terraform state.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
