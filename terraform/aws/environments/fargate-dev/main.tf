# ============================================================
# AWS — ECS Fargate, the LIVE compute path for this cloud (see
# terraform/aws/_reference-eks/README.md for the EKS path this
# replaced and its cost reasoning).
#
# Builds entirely on environments/dev's outputs (VPC, ECR, Secrets
# Manager containers) via terraform_remote_state — this file creates
# NO networking, NO ECR repos, and NO GitHub OIDC provider of its own.
#
# Rough monthly cost at the default sizing (5 services, min 1 / max
# 2-3 tasks each, 256 CPU / 512 MiB, mostly Fargate Spot): compute
# ~$10-15, ALB ~$16-20 (flat hourly charge + LCU usage), CloudWatch
# Logs a few dollars — roughly $40-60/month all in, NOT counting
# environments/dev's own VPC/NAT cost (~$32/month, already paid for
# regardless of which compute path is live). No EKS control plane fee
# exists in this path at all.
# ============================================================

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    stack       = "fargate"
    managed_by  = "terraform"
    owner       = "homeease"
  }

  resource_prefix = "homeease-${var.environment}"
  services        = ["backend", "admin-backend", "frontend", "admin-frontend", "payment-service"]
}

data "terraform_remote_state" "registry" {
  backend = "s3"

  config = {
    bucket = var.registry_state_bucket
    key    = var.registry_state_key
    region = var.region
  }
}

# ============================================================
# CLUSTER
# ============================================================

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  cluster_name   = local.resource_prefix
  namespace_name = "homeease.${var.environment}"

  tags = local.common_tags
}

# ============================================================
# LOAD BALANCER — public entry point for frontend + admin-frontend
# only, matching charts/frontend and charts/admin-frontend being the
# only two services with an Ingress in gitops_homeease.
# ============================================================

module "alb" {
  source = "../../modules/alb"

  environment       = var.environment
  vpc_id            = data.terraform_remote_state.registry.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.registry.outputs.public_subnet_ids

  tags = local.common_tags
}

# ============================================================
# TASK EXECUTION ROLES — three, not one, mirroring the exact same
# split already made twice on the other two clouds (Azure Workload
# Identity, AWS IRSA in _reference-eks): payment-service gets its own
# role because it is the one place a mistake has a real financial
# consequence. frontend/admin-frontend get a role with NO secrets
# access at all — they read none, matching "frontend needs neither"
# in gitops_homeease's README.
# ============================================================

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity", "sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---- web (frontend, admin-frontend): no secrets ----

resource "aws_iam_role" "exec_web" {
  name               = "${local.resource_prefix}-exec-web"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "exec_web" {
  role       = aws_iam_role.exec_web.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---- backend (backend, admin-backend): their own secrets ----

resource "aws_iam_role" "exec_backend" {
  name               = "${local.resource_prefix}-exec-backend"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "exec_backend" {
  role       = aws_iam_role.exec_backend.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "exec_backend_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      values(data.terraform_remote_state.registry.outputs.backend_secret_arns),
      values(data.terraform_remote_state.registry.outputs.admin_backend_secret_arns),
    )
  }
}

resource "aws_iam_role_policy" "exec_backend_secrets" {
  name   = "secrets-read"
  role   = aws_iam_role.exec_backend.id
  policy = data.aws_iam_policy_document.exec_backend_secrets.json
}

# ---- payment (payment-service only): own role, own blast radius ----

resource "aws_iam_role" "exec_payment" {
  name               = "${local.resource_prefix}-exec-payment"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "exec_payment" {
  role       = aws_iam_role.exec_payment.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "exec_payment_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(data.terraform_remote_state.registry.outputs.payment_secret_arns)
  }
}

resource "aws_iam_role_policy" "exec_payment_secrets" {
  name   = "secrets-read"
  role   = aws_iam_role.exec_payment.id
  policy = data.aws_iam_policy_document.exec_payment_secrets.json
}

# ============================================================
# SERVICES
#
# Ingress shape mirrors each service's charts/<service>/templates/
# networkpolicy.yaml exactly:
#   frontend, admin-frontend  — public, via the ALB
#   backend                   — internal, reachable from frontend +
#                                admin-frontend (both proxy /api/ to it)
#   admin-backend              — internal, reachable from admin-frontend
#                                only
#   payment-service            — internal, reachable from backend only
#                                (tightest — its NetworkPolicy is the
#                                one place this project scopes ingress
#                                to a single named peer, not "any pod")
# ============================================================

module "frontend" {
  source = "../../modules/ecs-service"

  name                          = "frontend"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  execution_role_arn            = aws_iam_role.exec_web.arn

  image                 = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/frontend:${var.image_tags.frontend}"
  container_port        = 8080
  attach_alb            = true
  alb_security_group_id = module.alb.security_group_id
  alb_target_group_arn  = module.alb.frontend_target_group_arn

  tags = local.common_tags
}

module "admin_frontend" {
  source = "../../modules/ecs-service"

  name                          = "admin-frontend"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  execution_role_arn            = aws_iam_role.exec_web.arn

  image                 = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/admin-frontend:${var.image_tags.admin_frontend}"
  container_port        = 8080
  attach_alb            = true
  alb_security_group_id = module.alb.security_group_id
  alb_target_group_arn  = module.alb.admin_frontend_target_group_arn

  tags = local.common_tags
}

module "backend" {
  source = "../../modules/ecs-service"

  name                          = "backend"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  execution_role_arn            = aws_iam_role.exec_backend.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/backend:${var.image_tags.backend}"
  container_port = 5000

  allowed_source_security_group_ids = {
    frontend       = module.frontend.security_group_id
    admin_frontend = module.admin_frontend.security_group_id
  }

  environment_variables = {
    NODE_ENV                  = "production"
    PORT                      = "5000"
    PAYMENT_SERVICE_URL       = "http://payment-service.homeease.${var.environment}:5002"
    ALLOWED_ORIGINS           = var.allowed_origins
    METRICS_COLLECTOR_ENABLED = "true"
  }

  secrets = {
    MONGO_URI  = data.terraform_remote_state.registry.outputs.backend_secret_arns["mongo-uri"]
    JWT_SECRET = data.terraform_remote_state.registry.outputs.backend_secret_arns["jwt-secret"]
    EMAIL_USER = data.terraform_remote_state.registry.outputs.backend_secret_arns["email-user"]
    EMAIL_PASS = data.terraform_remote_state.registry.outputs.backend_secret_arns["email-pass"]
  }

  tags = local.common_tags
}

module "admin_backend" {
  source = "../../modules/ecs-service"

  name                          = "admin-backend"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  execution_role_arn            = aws_iam_role.exec_backend.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/admin-backend:${var.image_tags.admin_backend}"
  container_port = 5001

  allowed_source_security_group_ids = { admin_frontend = module.admin_frontend.security_group_id }

  environment_variables = {
    NODE_ENV        = "production"
    PORT            = "5001"
    ALLOWED_ORIGINS = var.allowed_origins
  }

  secrets = {
    MONGO_URI  = data.terraform_remote_state.registry.outputs.admin_backend_secret_arns["mongo-uri"]
    JWT_SECRET = data.terraform_remote_state.registry.outputs.admin_backend_secret_arns["jwt-secret"]
  }

  tags = local.common_tags
}

module "payment_service" {
  source = "../../modules/ecs-service"

  name                          = "payment-service"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  execution_role_arn            = aws_iam_role.exec_payment.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/payment-service:${var.image_tags.payment_service}"
  container_port = 5002
  max_capacity   = 2 # matches this service's HPA maxReplicas in gitops_homeease

  # Tightest ingress in the stack, on purpose — see the block comment
  # above "SERVICES".
  allowed_source_security_group_ids = { backend = module.backend.security_group_id }

  environment_variables = {
    NODE_ENV             = "production"
    PORT                 = "5002"
    PAYMENT_SERVICE_PORT = "5002"
  }

  secrets = {
    RAZORPAY_KEY_ID         = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-key-id"]
    RAZORPAY_KEY_SECRET     = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-key-secret"]
    RAZORPAY_WEBHOOK_SECRET = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-webhook-secret"]
  }

  tags = local.common_tags
}

# ============================================================
# TERRAFORM-APPLY IDENTITY — this stack's own, via the shared
# tf-apply-role module (same one staging/prod already use). Extra
# ECS/ALB/autoscaling/networking permissions on top of the module's
# Budgets + ECRReadOnly baseline.
# ============================================================

data "aws_iam_policy_document" "tf_apply_extra" {
  statement {
    sid    = "ECS"
    effect = "Allow"
    # ECS's create/describe/update APIs are not ARN-scopable the way
    # S3 or ECR are — AWS's own managed policies for ECS use
    # Resource:"*" for exactly this reason. Scoped by IAM action set
    # instead: only what this stack's resources need, nothing
    # account-wide like ecs:DeleteCluster on clusters this stack
    # doesn't own (there's only ever one, but the action list itself
    # is the real boundary here, not a resource ARN).
    actions = [
      "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
      "ecs:PutClusterCapacityProviders",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices",
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition",
      "ecs:ListTagsForResource", "ecs:TagResource", "ecs:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ALB"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:*"]
    resources = ["*"]
  }

  statement {
    sid       = "ServiceConnect"
    effect    = "Allow"
    actions   = ["servicediscovery:*"]
    resources = ["*"]
  }

  statement {
    sid       = "AutoScaling"
    effect    = "Allow"
    actions   = ["application-autoscaling:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy", "logs:TagResource", "logs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # Security groups this stack's ecs-service/alb modules create. Not
  # scoped to specific group IDs — they don't exist until this policy
  # already needs to allow creating them.
  statement {
    sid    = "SecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags", "ec2:DescribeSubnets", "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  # The three execution roles this stack owns, and PassRole so ECS can
  # actually hand them to a running task — scoped by name prefix, same
  # discipline dev/main.tf's own tf_apply policy already uses for its
  # IAM statement.
  statement {
    sid    = "ExecutionRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.resource_prefix}-exec-*"]
  }

  # Read-only access to environments/dev's Secrets Manager containers,
  # needed only to resolve the data sources this file itself declares
  # — never a write action.
  statement {
    sid    = "SecretsRead"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:homeease/${var.environment}/*",
    ]
  }
}

module "tf_apply_role" {
  source = "../../modules/tf-apply-role"

  environment       = "fargate-${var.environment}"
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = data.terraform_remote_state.registry.outputs.oidc_provider_arn

  github_owner      = var.infra_github_owner
  github_repository = var.infra_github_repository
  allowed_branches  = ["main"]

  extra_policy_json = data.aws_iam_policy_document.tf_apply_extra.json

  tags = local.common_tags
}

# ============================================================
# COST GUARDRAIL — this stack's own budget, on top of
# environments/dev's. See this file's header comment for the estimate.
# ============================================================

resource "aws_budgets_budget" "monthly" {
  name         = "${local.resource_prefix}-fargate-monthly"
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
