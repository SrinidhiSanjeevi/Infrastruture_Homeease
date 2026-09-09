# ============================================================
# TERRAFORM-APPLY ROLE — for staging/prod, via the SAME GitHub OIDC
# provider dev's ci-oidc module already created.
#
# Not the same thing as ci-oidc's push role. That role lets the APP
# repo's workflow push images. This role lets the INFRA repo's
# workflow run `terraform plan`/`apply` against THIS environment's
# AWS resources — which today is just a budget, because CI never
# builds an image for staging or prod (see ANALYSIS.md §3: one
# digest, promoted, not rebuilt per environment).
#
# The OIDC provider is an account-wide singleton; only one may exist
# per URL. This module never creates it — it takes the ARN dev
# already produced and registers one more trust relationship against
# the same provider.
# ============================================================

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

    # Same discipline as ci-oidc: explicit prefixes, never a bare "*".
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

# Scoped to exactly what this environment manages today. Widen this
# (never to "*") the day EKS/VPC are added for this environment.
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

  # Read-only visibility into the shared registry dev owns — useful
  # once this environment's future EKS node role needs an ECR
  # repository policy, without granting any push permission here.
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
