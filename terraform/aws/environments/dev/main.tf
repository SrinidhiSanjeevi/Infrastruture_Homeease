# ============================================================
# AWS — registry, CI identity, VPC, and Secrets Manager containers.
#
# Compute-agnostic on purpose: this environment owns the resources any
# compute layer needs (ECR, the GitHub OIDC provider + CI push role,
# the VPC, Secrets Manager containers) but does NOT itself run any
# containers. The two compute options both build on top of this file
# rather than inside it:
#
#   - terraform/aws/environments/fargate-dev/  — ECS Fargate, LIVE path
#   - terraform/aws/_reference-eks/             — EKS, PARKED (see its
#     README for the ~$135/month baseline cost that moved it here —
#     $73 EKS control plane + $32 NAT Gateway + $30 one t3.medium node,
#     BEFORE autoscaling past 1 node, vs. Fargate's no-control-plane-fee
#     pricing for the same 5 services)
#
# THIS is the ONLY environment that owns the ECR repositories, the
# GitHub OIDC provider, and the VPC. All are account-wide or
# environment-defining singletons; staging/prod do NOT re-declare
# module.ecr — see their own main.tf for why. fargate-dev does not
# re-declare module.networking or module.ecr either — it references
# this environment's outputs.
# ============================================================

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "homeease"
  }

  resource_prefix = "homeease-${var.environment}"
}

# ============================================================
# NETWORKING — shared VPC. fargate-dev deploys its tasks and ALB into
# these same subnets (via terraform_remote_state); a second, separate
# VPC per compute option would just mean double NAT Gateway cost for
# no isolation benefit at this scale.
# ============================================================

module "networking" {
  source = "../../modules/networking"

  environment  = var.environment
  cluster_name = local.resource_prefix

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.common_tags
}

# ============================================================
# SECRETS MANAGER — containers only, no values (see
# modules/secrets/SECRETS.md). One prefix per service that actually
# needs secrets — matches Key Vault's per-service secret scoping on
# the Azure side, and mirrors exactly what a SecretProviderClass would
# list per service in gitops_homeease.
# ============================================================

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

module "payment_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/payment-service"
  secret_names = var.payment_secret_names

  tags = local.common_tags
}

# ============================================================
# ECR
# ============================================================

module "ecr" {
  source = "../../modules/ecr"

  namespace = "homeease"
  services  = ["backend", "admin-backend", "frontend", "admin-frontend", "payment-service"]

  retained_image_count = 15

  # Registry scanning config is account-wide. Set true here and false
  # everywhere else, or environments will fight over it on apply.
  manage_registry_scanning = true

  # Convenient on a trial account. Set false once anything matters.
  force_delete = true

  # No pull grant here on purpose. Fargate task pulls happen via a
  # task EXECUTION role with the AWS-managed
  # AmazonECSTaskExecutionRolePolicy attached (its ECR actions are
  # already resource:"*" by AWS's own design — see
  # modules/ci-oidc/main.tf's identical GetAuthorizationToken comment)
  # — no per-repository policy needed the way EKS's node role required
  # one. That role lives in environments/fargate-dev/main.tf. Keeping
  # this grant out of this shared, compute-agnostic environment means
  # _reference-eks (if ever re-applied) and fargate-dev never fight
  # over the same policy.
  pull_principal_arns = null

  tags = local.common_tags
}

# ============================================================
# CI IDENTITY — GitHub Actions (app repo) -> ECR push
# ============================================================

module "ci_oidc" {
  source = "../../modules/ci-oidc"

  github_owner      = var.github_owner
  github_repository = var.github_repository

  # Only main pushes. Fork PRs get the read role instead.
  allowed_branches = ["main"]
  create_read_role = true

  # Scoped to exactly these four repositories — not ["*"].
  ecr_repository_arns = values(module.ecr.repository_arns)

  create_oidc_provider = true

  # Names only. Values are set with `aws secretsmanager put-secret-value`,
  # never in Terraform — Terraform writes them to state in plaintext.
  ci_secret_names = []

  tags = local.common_tags
}

# ============================================================
# TERRAFORM-APPLY IDENTITY — infra repo -> THIS stack
#
# NOT module.ci_oidc's push role. That role can only push images to
# ECR; it has no IAM/ECR-admin/budget permissions and cannot run
# `terraform plan/apply` against this file. This is a separate role
# for the INFRA repo's GitHub Actions workflow, scoped to exactly
# what this stack manages: the ECR repos, the two ci-oidc roles +
# the OIDC provider itself, and the budget.
#
# CHICKEN-AND-EGG, same shape as the Azure ci-identity module: the
# very first `terraform apply` of this file has to be run by a human
# with real AWS credentials (aws sso login / IAM user), because until
# this role exists, GitHub Actions has nothing to assume. After that
# first apply, `terraform output tf_apply_role_arn` is what you paste
# into the infra repo's GitHub Environment variables — every
# subsequent plan/apply runs from CI.
# ============================================================

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

  # IAM management scoped to the resource NAMES this stack itself
  # creates — never iam:* / resources ["*"]. A Terraform-apply
  # identity that can create arbitrary IAM roles is a privilege
  # escalation path to the whole account.
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

# ============================================================
# COST GUARDRAIL
#
# EKS control plane is $0.10/hr per cluster with no free tier — about
# $73/month before a single node exists. On a $200 credit that is the
# line item most likely to surprise you. Set this now.
# ============================================================

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
