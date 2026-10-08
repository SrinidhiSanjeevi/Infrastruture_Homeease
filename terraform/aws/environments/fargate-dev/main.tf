# AWS — ECS Fargate, the LIVE compute path for this cloud

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

# CLUSTER

# Alarm topic. No email subscription for now, so alarms are visible in the CloudWatch console only.
resource "aws_sns_topic" "alarms" {
  name = "${local.resource_prefix}-alarms"
  tags = local.common_tags
}

# CloudWatch alarms need permission to publish to the topic.
data "aws_iam_policy_document" "alarms_topic" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # EventBridge delivers GuardDuty findings (security.tf) to the same topic.
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  container_insights = var.container_insights

  cluster_name   = local.resource_prefix
  namespace_name = "homeease.${var.environment}"

  tags = local.common_tags
}

# LOAD BALANCER — public entry point for frontend + admin-frontend only

module "alb" {
  source = "../../modules/alb"

  environment       = var.environment
  vpc_id            = data.terraform_remote_state.registry.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.registry.outputs.public_subnet_ids
  certificate_arn   = var.certificate_arn
  alarm_topic_arn   = aws_sns_topic.alarms.arn

  tags = local.common_tags
}

# HTTPS without a domain
module "cloudfront" {
  source = "../../modules/cloudfront"

  environment  = var.environment
  alb_dns_name = module.alb.dns_name

  tags = local.common_tags
}

# TASK EXECUTION ROLES — three, not one

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

# web (frontend, admin-frontend)

resource "aws_iam_role" "exec_web" {
  name               = "${local.resource_prefix}-exec-web"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "exec_web" {
  role       = aws_iam_role.exec_web.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# backend (backend, admin-backend)

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

# notification (notification-service only)

resource "aws_iam_role" "exec_notification" {
  name               = "${local.resource_prefix}-exec-notification"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "exec_notification" {
  role       = aws_iam_role.exec_notification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "exec_notification_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(data.terraform_remote_state.registry.outputs.notification_secret_arns)
  }
}

resource "aws_iam_role_policy" "exec_notification_secrets" {
  name   = "secrets-read"
  role   = aws_iam_role.exec_notification.id
  policy = data.aws_iam_policy_document.exec_notification_secrets.json
}

# payment (payment-service only)

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

# SERVICES

module "frontend" {
  source = "../../modules/ecs-service"

  name                          = "frontend"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_web.arn

  image                 = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/frontend:${var.image_tags.frontend}"
  container_port        = 8080
  health_check_path     = "/health"
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
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_web.arn

  image                 = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/admin-frontend:${var.image_tags.admin_frontend}"
  container_port        = 8080
  health_check_path     = "/health"
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
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_backend.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/backend:${var.image_tags.backend}"
  container_port = 5000

  # Callers of the booking backend: both frontends and the three internal services
  allowed_source_security_group_ids = {
    frontend             = module.frontend.security_group_id
    admin_frontend       = module.admin_frontend.security_group_id
    admin_backend        = module.admin_backend.security_group_id
    payment_service      = module.payment_service.security_group_id
    notification_service = module.notification_service.security_group_id
  }

  environment_variables = {
    NODE_ENV                 = "production"
    PORT                     = "5000"
    PAYMENT_SERVICE_URL      = "http://payment-service:5002"
    NOTIFICATION_SERVICE_URL = "http://notification-service:5003"
    # No Prometheus on AWS: publish business metrics to CloudWatch via EMF
    CLOUDWATCH_EMF_ENABLED = "true"
    # ALB + frontend nginx + Service Connect sidecar sit in front of the backend
    TRUST_PROXY_HOPS = "2"
    # Demo: shared wifi IPs hit the default rate limits
    RATE_LIMIT_AUTH_MAX       = "300"
    RATE_LIMIT_GENERAL_MAX    = "5000"
    RATE_LIMIT_PAYMENT_MAX    = "200"
    RATE_LIMIT_EMERGENCY_MAX  = "200"
    ALLOWED_ORIGINS           = var.allowed_origins
    METRICS_COLLECTOR_ENABLED = "true"
    # Images live in Azure Blob (persistent/azure-storage)
    AZURE_STORAGE_ACCOUNT_NAME = var.azure_storage_account_name
  }

  secrets = {
    MONGO_URI  = data.terraform_remote_state.registry.outputs.backend_secret_arns["mongo-uri"]
    JWT_SECRET = data.terraform_remote_state.registry.outputs.backend_secret_arns["jwt-secret"]
    EMAIL_USER = data.terraform_remote_state.registry.outputs.backend_secret_arns["email-user"]
    EMAIL_PASS = data.terraform_remote_state.registry.outputs.backend_secret_arns["email-pass"]

    AZURE_STORAGE_ACCOUNT_KEY = data.terraform_remote_state.registry.outputs.backend_secret_arns["azure-storage-account-key"]
  }
  # HA: raise the autoscaling floor to two tasks, which ECS places across both AZs.
  min_capacity = 2

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
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_backend.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/admin-backend:${var.image_tags.admin_backend}"
  container_port = 5001

  allowed_source_security_group_ids = { admin_frontend = module.admin_frontend.security_group_id }

  environment_variables = {
    NODE_ENV        = "production"
    PORT            = "5001"
    ALLOWED_ORIGINS = var.allowed_origins

    # Admin reads bookings/users through the booking service
    BOOKING_SERVICE_URL = "http://backend:5000"
    TRUST_PROXY_HOPS    = "2"

    AZURE_STORAGE_ACCOUNT_NAME = var.azure_storage_account_name
  }

  secrets = {
    MONGO_URI  = data.terraform_remote_state.registry.outputs.admin_backend_secret_arns["mongo-uri"]
    JWT_SECRET = data.terraform_remote_state.registry.outputs.admin_backend_secret_arns["jwt-secret"]

    AZURE_STORAGE_ACCOUNT_KEY = data.terraform_remote_state.registry.outputs.admin_backend_secret_arns["azure-storage-account-key"]
  }
  # HA: raise the autoscaling floor to two tasks, which ECS places across both AZs.
  min_capacity = 2

  tags = local.common_tags
}

module "notification_service" {
  source = "../../modules/ecs-service"

  name                          = "notification-service"
  environment                   = var.environment
  cluster_id                    = module.ecs_cluster.cluster_id
  cluster_name                  = module.ecs_cluster.cluster_name
  vpc_id                        = data.terraform_remote_state.registry.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.registry.outputs.private_subnet_ids
  service_connect_namespace_arn = module.ecs_cluster.namespace_arn
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_notification.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/notification-service:${var.image_tags.notification_service}"
  container_port = 5003
  max_capacity   = 2

  # Only the booking backend sends notifications.
  allowed_source_security_group_ids = { backend = module.backend.security_group_id }

  environment_variables = {
    NODE_ENV                  = "production"
    PORT                      = "5003"
    NOTIFICATION_SERVICE_PORT = "5003"
    BOOKING_SERVICE_URL       = "http://backend:5000"
  }

  secrets = {
    MONGO_URI  = data.terraform_remote_state.registry.outputs.notification_secret_arns["mongo-uri"]
    EMAIL_USER = data.terraform_remote_state.registry.outputs.notification_secret_arns["email-user"]
    EMAIL_PASS = data.terraform_remote_state.registry.outputs.notification_secret_arns["email-pass"]
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
  alarm_topic_arn               = aws_sns_topic.alarms.arn
  execution_role_arn            = aws_iam_role.exec_payment.arn

  image          = "${data.terraform_remote_state.registry.outputs.registry_url}/homeease/payment-service:${var.image_tags.payment_service}"
  container_port = 5002
  max_capacity   = 2 # matches this service's HPA maxReplicas in gitops_homeease

  # HA: raise the autoscaling floor to two tasks, which ECS places across both AZs.
  min_capacity = 2

  # Tightest ingress in the stack, on purpose
  allowed_source_security_group_ids = { backend = module.backend.security_group_id }

  environment_variables = {
    NODE_ENV             = "production"
    PORT                 = "5002"
    PAYMENT_SERVICE_PORT = "5002"
    # Publish the DB-backed payment gauges to CloudWatch (no Prometheus on AWS).
    CLOUDWATCH_EMF_ENABLED = "true"

    # Payment confirms/creates payments against the booking service.
    BOOKING_SERVICE_URL = "http://backend:5000"
  }

  secrets = {
    MONGO_URI               = data.terraform_remote_state.registry.outputs.payment_secret_arns["mongo-uri"]
    RAZORPAY_KEY_ID         = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-key-id"]
    RAZORPAY_KEY_SECRET     = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-key-secret"]
    RAZORPAY_WEBHOOK_SECRET = data.terraform_remote_state.registry.outputs.payment_secret_arns["razorpay-webhook-secret"]
  }

  tags = local.common_tags
}

# TERRAFORM-APPLY IDENTITY — this stack's own, via the shared tf-apply-role module

data "aws_iam_policy_document" "tf_apply_extra" {
  statement {
    sid    = "ECS"
    effect = "Allow"
    # ECS's create/describe/update APIs are not ARN-scopable the way S3 or ECR are
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
    sid       = "ClusterSettings"
    effect    = "Allow"
    actions   = ["ecs:UpdateCluster", "ecs:UpdateClusterSettings"]
    resources = ["*"]
  }

  statement {
    sid    = "Dashboard"
    effect = "Allow"
    actions = [
      "cloudwatch:PutDashboard", "cloudwatch:DeleteDashboards",
      "cloudwatch:GetDashboard", "cloudwatch:ListDashboards",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Alarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AlarmTopic"
    effect = "Allow"
    actions = [
      "sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes",
      "sns:Subscribe", "sns:Unsubscribe", "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic", "sns:ListTagsForResource", "sns:TagResource",
    ]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${local.resource_prefix}-*"]
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

  # Security groups this stack's ecs-service/alb modules create.
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

  # The stack's three execution roles, plus PassRole for ECS
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

  # Read-only access to environments/dev's Secrets Manager containers
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

# COST GUARDRAIL — this stack's own budget, on top of environments/dev's.

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
