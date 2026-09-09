# ============================================================
# GITHUB ACTIONS → AWS, VIA OIDC
#
# No IAM user. No access key ID. No secret access key. If you ever
# find yourself creating an aws_iam_access_key for CI, stop — this
# module is the reason you don't have to.
#
# The flow:
#   1. The workflow requests an OIDC token from GitHub (needs
#      `permissions: id-token: write`).
#   2. It calls sts:AssumeRoleWithWebIdentity presenting that token.
#   3. STS validates the signature against the OIDC provider below,
#      then checks the trust policy conditions.
#   4. It returns credentials valid for one hour.
#
# EVERYTHING depends on step 3 being written correctly.
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

# ============================================================
# OIDC PROVIDER
#
# Account-wide singleton. If another stack in this account already
# created it, set create_oidc_provider = false and pass the ARN in —
# a duplicate provider for the same URL is an error.
#
# thumbprint_list: AWS stopped requiring thumbprint validation for
# this provider in 2023 and now uses its own trust store, but the
# API still accepts the field. Kept for compatibility; do not treat
# it as a security control.
# ============================================================

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
  #
  # What NOT to write:
  #   "repo:owner/repo:*"
  #
  # That wildcard trusts every branch, every tag, and every
  # pull_request context in the repository. A contributor who opens a
  # PR from a fork can then run a workflow that assumes your push
  # role. It is the most common OIDC misconfiguration and it is a full
  # registry compromise.
  #
  # Instead: pin refs explicitly, and use GitHub Environment subjects
  # (`environment:prod`) for anything privileged, because Environments
  # can require human approval before the token is minted at all.
  push_subjects = concat(
    [for b in var.allowed_branches : "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${b}"],
    [for e in var.allowed_environments : "repo:${var.github_owner}/${var.github_repository}:environment:${e}"],
    var.allow_tags ? ["repo:${var.github_owner}/${var.github_repository}:ref:refs/tags/*"] : []
  )
}

# ============================================================
# PUSH ROLE — main branch only
# ============================================================

data "aws_iam_policy_document" "push_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Audience must match exactly. StringEquals, never StringLike.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Subject may need a wildcard for tag refs, hence StringLike —
    # but the values are explicit prefixes, not a bare "*".
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.push_subjects
    }
  }
}

resource "aws_iam_role" "push" {
  name                 = var.push_role_name
  description          = "HomeEase CI — pushes container images to ECR. Assumed via GitHub OIDC; has no long-lived credentials."
  assume_role_policy   = data.aws_iam_policy_document.push_assume.json
  max_session_duration = 3600

  tags = var.tags
}

data "aws_iam_policy_document" "push" {
  # GetAuthorizationToken cannot be scoped to a resource — the API
  # returns a token for the whole registry and AWS models it as "*".
  # This is expected, not a mistake in the policy.
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything that CAN be scoped, IS scoped — to the exact repository
  # ARNs created by the ecr module, not to ecr:*.
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

# ============================================================
# READ ROLE — pull requests
#
# A PR from a fork runs untrusted code. It gets a role that can read
# scan findings and describe images, and nothing else. This is why
# the two roles are separate rather than one role with a branch
# condition: separation is structural, not conditional.
# ============================================================

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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "read" {
  count = var.create_read_role ? 1 : 0

  name                 = "${var.push_role_name}-read"
  description          = "HomeEase CI — read-only, assumed by pull request workflows. Cannot write to any registry."
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

# ============================================================
# SECRETS — reference, never create
#
# The secret VALUE is set out of band (console or CLI). Terraform
# manages the container and the access grant only. Putting a real
# secret in a Terraform resource writes it to state in plaintext,
# and state is a file that gets copied around.
# ============================================================

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
