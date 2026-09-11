# ============================================================
# AWS — full stack: registry, CI identity, VPC, and EKS.
#
# This started as CI/registry-only (no VPC, no EKS, no NAT Gateway —
# see git history / ANALYSIS.md §8-9 for that reasoning) so the image
# pipeline could exist and be tested before paying for the expensive
# parts. This is that second phase: a real cluster, mirroring
# terraform/azure's AKS stack resource-for-resource (VPC ~ VNet, EKS ~
# AKS, IRSA ~ Workload Identity, Secrets Manager ~ Key Vault).
#
# What this costs to run, roughly, once applied: EKS control plane
# ~$73/month (flat, no free tier) + one NAT Gateway ~$32/month + one
# t3.medium node ~$30/month ≈ $135/month baseline BEFORE autoscaling
# past 1 node. That's already well past the $50 budget default below
# — raise monthly_budget_amount in terraform.tfvars before applying,
# or destroy the eks/networking modules between demos the same way the
# original comment here suggested doing for all of EKS.
#
# THIS is also the ONLY environment that owns the ECR repositories,
# the GitHub OIDC provider, the VPC, and the EKS cluster. All are
# account-wide or environment-defining singletons; staging/prod do NOT
# re-declare module.ecr or module.eks — see their own main.tf for why.
# ============================================================

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "homeease"
  }

  cluster_name = "eks-homeease-${var.environment}"
}

# ============================================================
# NETWORKING
# ============================================================

module "networking" {
  source = "../../modules/networking"

  environment  = var.environment
  cluster_name = local.cluster_name

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.common_tags
}

# ============================================================
# EKS
# ============================================================

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = local.common_tags
}

# ============================================================
# SECRETS MANAGER — payment-service's Razorpay credentials only. See
# modules/secrets/SECRETS.md for how the values themselves get set
# (never by Terraform).
# ============================================================

module "payment_secrets" {
  source = "../../modules/secrets"

  name_prefix  = "homeease/${var.environment}/payment-service"
  secret_names = var.payment_secret_names

  tags = local.common_tags
}

# ============================================================
# IRSA — payment-service's own IAM role, own blast radius. Mirrors
# module.workload_identity_payment on the Azure side exactly, down to
# the same TODO: this shares nothing with backend/admin-backend by
# design (payment-service is the one place a mistake has a real
# financial consequence — see gitops_homeease's
# apps/payment-service/base/networkpolicy.yaml for the rest of that
# reasoning).
# ============================================================

module "irsa_payment" {
  source = "../../modules/irsa"

  role_name = "homeease-${var.environment}-payment-service"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Matches the GitOps repo's namespace-per-environment design
  # (homeease-dev / homeease-staging / homeease-prod) — see
  # gitops_homeease/apps/payment-service/overlays/aws/dev/kustomization.yaml.
  namespace            = var.kubernetes_namespace
  service_account_name = "payment-service"

  secret_arns = values(module.payment_secrets.secret_arns)

  tags = local.common_tags
}

# ============================================================
# ECR
# ============================================================

module "ecr" {
  source = "../../modules/ecr"

  namespace = "homeease"
  services  = ["backend", "admin-backend", "frontend", "payment-service"]

  retained_image_count = 15

  # Registry scanning config is account-wide. Set true here and false
  # everywhere else, or environments will fight over it on apply.
  manage_registry_scanning = true

  # Convenient on a trial account. Set false once anything matters.
  force_delete = true

  # The node role only — IRSA (module.irsa_payment) handles
  # application identity for secrets, not image pulls. Pods never pull
  # their own images; the kubelet does, using the node's role, before
  # any pod (and therefore any ServiceAccount) exists.
  pull_principal_arns = [module.eks.node_role_arn]

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
