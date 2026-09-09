# ============================================================
# ECR — one repository per service, path-namespaced to match ACR
#
#   ACR:  acrhomeeasedev.azurecr.io/homeease/backend:<sha>
#   ECR:  <acct>.dkr.ecr.ap-south-1.amazonaws.com/homeease/backend:<sha>
#
# Same path, same tag, same digest content — so a manifest can switch
# clouds by changing the registry host and nothing else.
# ============================================================

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

  # THE important line. IMMUTABLE means ECR rejects a push to a tag
  # that already exists. It is what turns "don't use :latest" from a
  # convention people forget into something the registry enforces.
  # It also guarantees that a tag seen in a manifest today resolves to
  # the same bytes tomorrow — which is the whole basis of being able
  # to roll back.
  image_tag_mutability = "IMMUTABLE"

  # Free. The enhanced (Inspector-backed) alternative is billed per
  # image scanned and should stay off while you are on trial credit.
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

# ============================================================
# LIFECYCLE POLICY
#
# Free-tier storage protection. Without this, every CI run adds a
# layer set that is never removed, and a monorepo with four services
# building on every merge fills 500 MB in weeks.
#
# Rules evaluate in priority order, first match wins.
# ============================================================

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

# ============================================================
# REPOSITORY POLICY
#
# Explicit allow for the EKS node role to pull. IRSA handles
# application identity; image pulls happen before any pod exists, so
# they use the NODE role, not a service account.
# ============================================================

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

# ============================================================
# REGISTRY-WIDE SCANNING
#
# Registry-level configuration, so it is set once rather than per
# repository. BASIC is free and gives you a second opinion alongside
# Trivy — they use different vulnerability sources and genuinely
# disagree, which is the point of running both.
# ============================================================

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
