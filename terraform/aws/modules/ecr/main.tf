# ECR — one repository per service, path-namespaced to match ACR

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name = "${var.namespace}/${each.value}"

  # IMMUTABLE: ECR rejects a push to an existing tag
  image_tag_mutability = "IMMUTABLE"

  # Basic scanning is free; enhanced (Inspector) scanning is billed per image
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = var.force_delete

  tags = merge(var.tags, {
    service = each.value
  })
}

# LIFECYCLE POLICY

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day — these are orphaned layers from failed or superseded pushes"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last ${var.retained_image_count} images — enough history to roll back several deploys"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.retained_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# REPOSITORY POLICY

resource "aws_ecr_repository_policy" "pull" {
  for_each = var.pull_principal_arns == null ? {} : aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowClusterPull"
        Effect = "Allow"
        Principal = {
          AWS = var.pull_principal_arns
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# REGISTRY-WIDE SCANNING

resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.manage_registry_scanning ? 1 : 0

  scan_type = "BASIC"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "${var.namespace}/*"
      filter_type = "WILDCARD"
    }
  }
}
