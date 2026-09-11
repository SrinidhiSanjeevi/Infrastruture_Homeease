# ============================================================
# IRSA (IAM Roles for Service Accounts) — mirrors
# terraform/azure/modules/workload-identity: a per-service IAM role a
# Kubernetes ServiceAccount can assume, with no long-lived credential
# stored in the cluster.
#
# Simpler than the Azure module in one respect: Azure needs one
# azurerm_federated_identity_credential PER ServiceAccount (see that
# module's "additional" resource). AWS's OIDC trust-policy condition
# accepts a LIST of subjects in a single StringEquals check, so one
# role + one trust statement covers the primary ServiceAccount and any
# additional_service_accounts without repeating a whole resource block.
# ============================================================

locals {
  subjects = concat(
    ["system:serviceaccount:${var.namespace}:${var.service_account_name}"],
    [for sa in var.additional_service_accounts : "system:serviceaccount:${sa.namespace}:${sa.service_account_name}"]
  )
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
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  description        = "HomeEase IRSA role for ${var.namespace}/${var.service_account_name}. Assumed via the EKS cluster's OIDC provider; no long-lived credentials."
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

# ============================================================
# SECRETS MANAGER ACCESS — read-only, scoped to exactly the ARNs
# passed in. This role never gets PutSecretValue — see
# modules/secrets/SECRETS.md for who does and how values are set.
# ============================================================

data "aws_iam_policy_document" "secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name   = "secrets-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.secrets[0].json
}
