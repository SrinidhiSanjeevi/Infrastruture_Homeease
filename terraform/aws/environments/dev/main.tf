# AWS — registry, CI identity, VPC, and Secrets Manager containers.

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "homeease"
  }

  resource_prefix = "homeease-${var.environment}"
}

# NETWORKING — shared VPC.

module "networking" {
  source = "../../modules/networking"

  environment  = var.environment
  cluster_name = local.resource_prefix

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.common_tags
}

# SECRETS MANAGER — containers only, no values (see modules/secrets/SECRETS.md).

module "backend_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/backend"
  secret_names = ["mongo-uri", "jwt-secret", "email-user", "email-pass", "azure-storage-account-key"]

  tags = local.common_tags
}

module "admin_backend_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/admin-backend"
  secret_names = ["mongo-uri", "jwt-secret", "azure-storage-account-key"]

  tags = local.common_tags
}

module "notification_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/notification-service"
  secret_names = ["mongo-uri", "email-user", "email-pass"]

  tags = local.common_tags
}

module "payment_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/payment-service"
  secret_names = var.payment_secret_names

  tags = local.common_tags
}

# ECR

module "ecr" {
  source = "../../modules/ecr"

  namespace = "homeease"
  services  = ["backend", "admin-backend", "frontend", "admin-frontend", "payment-service", "notification-service"]

  retained_image_count = 15

  # Registry scanning config is account-wide.
  manage_registry_scanning = true

  # Trial account convenience; set false once anything matters.
  force_delete = true

  # No pull grant here on purpose.
  pull_principal_arns = null

  tags = local.common_tags
}

# CI IDENTITY — GitHub Actions (app repo) -> ECR push

module "ci_oidc" {
  source = "../../modules/ci-oidc"

  github_owner      = var.github_owner
  github_repository = var.github_repository

  # Only main pushes. Fork PRs get the read role instead.
  allowed_branches = ["main"]
  create_read_role = true

  # Scoped to exactly these four repositories
  ecr_repository_arns = values(module.ecr.repository_arns)

  create_oidc_provider = true

  # Names only. Values are set with `aws secretsmanager put-secret-value`, never in Terraform
  ci_secret_names = []

  tags = local.common_tags
}

# TERRAFORM-APPLY IDENTITY — infra repo -> this stack

data "aws_iam_policy_document" "tf_apply_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.ci_oidc.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.infra_github_owner}/${var.infra_github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name                 = "homeease-tf-apply-${var.environment}"
  description          = "HomeEase infra-repo Terraform apply for ${var.environment}. Assumed via GitHub OIDC; no long-lived credentials."
  assume_role_policy   = data.aws_iam_policy_document.tf_apply_assume.json
  max_session_duration = 3600

  tags = local.common_tags
}

data "aws_iam_policy_document" "tf_apply" {
  statement {
    sid    = "ECRAdmin"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutRegistryScanningConfiguration",
      "ecr:GetRegistryScanningConfiguration",
      "ecr:TagResource",
      "ecr:ListTagsForResource"
    ]
    resources = ["*"]
  }

  # IAM management scoped to the resource NAMES this stack itself creates
  statement {
    sid    = "IAMScopedToOwnResources"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/homeease-ci-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/homeease-tf-apply-*"
    ]
  }

  statement {
    sid    = "OIDCProvider"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
  }

  statement {
    sid    = "Budgets"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget"
    ]
    resources = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/*"]
  }
}

resource "aws_iam_role_policy" "tf_apply" {
  name   = "tf-apply"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply.json
}

# COST GUARDRAIL

resource "aws_budgets_budget" "monthly" {
  name         = "homeease-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_contact_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_contact_emails
  }
}
