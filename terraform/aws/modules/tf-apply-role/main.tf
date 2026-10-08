# TERRAFORM-APPLY ROLE — for staging/prod

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Same discipline as ci-oidc
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [for b in var.allowed_branches :
        "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${b}"
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "homeease-tf-apply-${var.environment}"
  description          = "HomeEase infra-repo Terraform apply for ${var.environment}. Assumed via GitHub OIDC; no long-lived credentials."
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = var.tags
}

# Scoped to exactly what this environment manages today.
data "aws_iam_policy_document" "permissions" {
  statement {
    sid    = "Budgets"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
      "budgets:DescribeBudgetAction*"
    ]
    resources = ["arn:aws:budgets::${var.account_id}:budget/*"]
  }

  # Read-only visibility into the shared registry dev owns
  statement {
    sid    = "ECRReadOnly"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "tf-apply"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

# EXTRA PERMISSIONS — for an environment that manages more than budgets + registry read

resource "aws_iam_role_policy" "extra" {
  count = var.extra_policy_json != null ? 1 : 0

  name   = "tf-apply-extra"
  role   = aws_iam_role.this.id
  policy = var.extra_policy_json
}
