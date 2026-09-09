# ============================================================
# AWS — prod, CI/registry scope only
#
# Does NOT re-declare module.ecr or create a second GitHub OIDC
# provider — both are account-wide singletons already created by
# dev/main.tf. See that file's header comment.
#
# What prod DOES need: its own Terraform state key, its own
# least-privilege identity for the infra repo's GitHub Actions
# workflow to plan/apply THIS environment, and its own budget so
# cost is tracked per environment even before any compute exists
# here. Prefer gating this environment's GitHub Environment with
# required reviewers, since "prod" should never auto-apply.
# ============================================================

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "homeease"
  }
}

module "tf_apply_role" {
  source = "../../modules/tf-apply-role"

  environment       = var.environment
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = var.oidc_provider_arn

  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = ["main"]

  tags = local.common_tags
}

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
