# ============================================================
# OPT-IN: role for decommissioning the Fargate stack from GitHub Actions.
#
# Why it exists: environments/fargate-dev's own apply role is destroyed WITH that stack (and has no S3
# state permission), so it cannot be the identity that destroys it. A destroy needs delete rights across
# ECS, ALB, CloudFront, CloudWatch, SNS, IAM, which is broad by nature.
#
# Why it is off by default: PowerUserAccess is account-wide. Turn it on for the teardown window only,
# run .github/workflows/aws-fargate-destroy.yml, then set create_fargate_teardown_role = false and apply.
# Trust is limited to this repository's main branch through GitHub OIDC; no long-lived key exists.
# ============================================================

data "aws_iam_policy_document" "teardown_assume" {
  count = var.create_fargate_teardown_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.registry.oidc_provider_arn]
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

resource "aws_iam_role" "fargate_teardown" {
  count = var.create_fargate_teardown_role ? 1 : 0

  name                 = "homeease-tf-teardown-fargate"
  description          = "Opt-in: lets aws-fargate-destroy.yml decommission environments/fargate-dev. Remove after use."
  assume_role_policy   = data.aws_iam_policy_document.teardown_assume[0].json
  max_session_duration = 3600

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_teardown_power_user" {
  count = var.create_fargate_teardown_role ? 1 : 0

  role       = aws_iam_role.fargate_teardown[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "teardown_extra" {
  count = var.create_fargate_teardown_role ? 1 : 0

  statement {
    sid       = "TerraformState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.registry_state_bucket}/aws/*"]
  }

  # PowerUserAccess excludes IAM. The Fargate stack owns task execution roles and its own apply role.
  statement {
    sid    = "HomeEaseIAMOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:ListInstanceProfilesForRole",
      "iam:CreateServiceLinkedRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/homeease-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*",
    ]
  }
}

resource "aws_iam_role_policy" "fargate_teardown_extra" {
  count = var.create_fargate_teardown_role ? 1 : 0

  name   = "teardown-extra"
  role   = aws_iam_role.fargate_teardown[0].id
  policy = data.aws_iam_policy_document.teardown_extra[0].json
}
