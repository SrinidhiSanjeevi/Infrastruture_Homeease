# GITHUB ACTIONS → AWS, VIA OIDC

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

# OIDC PROVIDER

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # These are the subjects allowed to assume the PUSH role.
  push_subjects = concat(
    flatten([for b in var.allowed_branches : [
      "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${b}",
      "repo:${var.github_owner}@*/${var.github_repository}@*:ref:refs/heads/${b}",
    ]]),
    flatten([for e in var.allowed_environments : [
      "repo:${var.github_owner}/${var.github_repository}:environment:${e}",
      "repo:${var.github_owner}@*/${var.github_repository}@*:environment:${e}",
    ]]),
    var.allow_tags ? [
      "repo:${var.github_owner}/${var.github_repository}:ref:refs/tags/*",
      "repo:${var.github_owner}@*/${var.github_repository}@*:ref:refs/tags/*",
    ] : []
  )
}

# PUSH ROLE — main branch only

data "aws_iam_policy_document" "push_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Audience must match exactly.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Subject may need a wildcard for tag refs, hence StringLike
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.push_subjects
    }
  }
}

resource "aws_iam_role" "push" {
  name                 = var.push_role_name
  description          = "HomeEase CI - pushes container images to ECR. Assumed via GitHub OIDC; has no long-lived credentials."
  assume_role_policy   = data.aws_iam_policy_document.push_assume.json
  max_session_duration = 3600

  tags = var.tags
}

data "aws_iam_policy_document" "push" {
  # GetAuthorizationToken cannot be scoped to a resource
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything that CAN be scoped, IS scoped
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "push" {
  name   = "ecr-push"
  role   = aws_iam_role.push.id
  policy = data.aws_iam_policy_document.push.json
}

# READ ROLE — pull requests

data "aws_iam_policy_document" "read_assume" {
  count = var.create_read_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike, not StringEquals (same reasoning as push_subjects)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/${var.github_repository}:pull_request",
        "repo:${var.github_owner}@*/${var.github_repository}@*:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "read" {
  count = var.create_read_role ? 1 : 0

  name                 = "${var.push_role_name}-read"
  description          = "HomeEase CI - read-only, assumed by pull request workflows. Cannot write to any registry."
  assume_role_policy   = data.aws_iam_policy_document.read_assume[0].json
  max_session_duration = 3600

  tags = var.tags
}

data "aws_iam_policy_document" "read" {
  count = var.create_read_role ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "read" {
  count = var.create_read_role ? 1 : 0

  name   = "ecr-read"
  role   = aws_iam_role.read[0].id
  policy = data.aws_iam_policy_document.read[0].json
}

# SECRETS — reference, never create; values are set out of band

data "aws_secretsmanager_secret" "ci" {
  for_each = toset(var.ci_secret_names)
  name     = each.value
}

data "aws_iam_policy_document" "secrets" {
  count = length(var.ci_secret_names) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for s in data.aws_secretsmanager_secret.ci : s.arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  count = length(var.ci_secret_names) > 0 ? 1 : 0

  name   = "ci-secrets-read"
  role   = aws_iam_role.push.id
  policy = data.aws_iam_policy_document.secrets[0].json
}
