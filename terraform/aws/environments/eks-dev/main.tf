# AWS - EKS + Argo CD (GitOps), the Kubernetes path for this cloud.

locals {
  common_tags = {
    project     = "homeease"
    environment = var.environment
    stack       = "eks"
    managed_by  = "terraform"
    owner       = "homeease"
  }

  # IRSA role names derive from this
  cluster_name = "homeease-eks-${var.environment}"

  registry = data.terraform_remote_state.registry.outputs
}

data "terraform_remote_state" "registry" {
  backend = "s3"

  config = {
    bucket = var.registry_state_bucket
    key    = var.registry_state_key
    region = var.region
  }
}

# SUBNET DISCOVERY TAGS

locals {
  subnet_tags = merge(
    { for id in local.registry.public_subnet_ids : "${id}|elb" => { id = id, key = "kubernetes.io/role/elb", value = "1" } },
    { for id in local.registry.private_subnet_ids : "${id}|internal-elb" => { id = id, key = "kubernetes.io/role/internal-elb", value = "1" } },
    { for id in concat(local.registry.public_subnet_ids, local.registry.private_subnet_ids) :
    "${id}|cluster" => { id = id, key = "kubernetes.io/cluster/${local.cluster_name}", value = "shared" } },
  )
}

resource "aws_ec2_tag" "subnet" {
  for_each = local.subnet_tags

  resource_id = each.value.id
  key         = each.value.key
  value       = each.value.value
}

# CLUSTER

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  private_subnet_ids = local.registry.private_subnet_ids
  public_subnet_ids  = local.registry.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  ecr_repository_arns = values(local.registry.repository_arns)
  public_access_cidrs = var.public_access_cidrs

  # Access is declared below (aws_eks_access_entry), not inherited from whoever runs apply.
  bootstrap_creator_admin = false

  tags = local.common_tags

  depends_on = [aws_ec2_tag.subnet]
}

# CLUSTER ACCESS - who can run kubectl / helm against the cluster.

locals {
  # STATIC keys: for_each keys must be known at plan, the CI role ARN is not
  cluster_admins = merge(
    { for arn in var.cluster_admin_principal_arns : arn => arn },
    { "ci-apply-role" = module.tf_apply_role.role_arn },
  )
}

resource "aws_eks_access_entry" "admin" {
  for_each = local.cluster_admins

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = local.cluster_admins

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# IRSA - one role per blast radius, mirroring the three Azure workload identities

module "irsa_app" {
  source = "../../modules/irsa"

  role_name            = "${local.cluster_name}-app"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = var.kubernetes_namespace
  service_account_name = "backend"
  additional_service_accounts = [
    { namespace = var.kubernetes_namespace, service_account_name = "admin-backend" },
  ]

  secret_arns = concat(
    values(local.registry.backend_secret_arns),
    values(local.registry.admin_backend_secret_arns),
  )

  tags = local.common_tags
}

module "irsa_payment" {
  source = "../../modules/irsa"

  role_name            = "${local.cluster_name}-payment"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = var.kubernetes_namespace
  service_account_name = "payment-service"

  secret_arns = values(local.registry.payment_secret_arns)

  tags = local.common_tags
}

module "irsa_notification" {
  source = "../../modules/irsa"

  role_name            = "${local.cluster_name}-notification"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = var.kubernetes_namespace
  service_account_name = "notification-service"

  secret_arns = values(local.registry.notification_secret_arns)

  tags = local.common_tags
}

# HTTPS - CloudFront in front of the two ingress NLBs (same idea as fargate-dev, different origin).

data "aws_lb" "ingress_customer" {
  count = var.enable_cloudfront ? 1 : 0

  tags = { "homeease-ingress" = "customer" }
}

data "aws_lb" "ingress_admin" {
  count = var.enable_cloudfront ? 1 : 0

  tags = { "homeease-ingress" = "admin" }
}

module "cloudfront" {
  source = "../../modules/cloudfront"
  count  = var.enable_cloudfront ? 1 : 0

  environment = "eks-${var.environment}"

  app_origin_dns_name   = data.aws_lb.ingress_customer[0].dns_name
  admin_origin_dns_name = data.aws_lb.ingress_admin[0].dns_name
  app_origin_port       = 80
  admin_origin_port     = 80 # own NLB, so no 8081 split as on the shared ALB

  tags = local.common_tags
}

# APPLY ROLE - lets the infra repo's GitHub Actions workflow

data "aws_iam_policy_document" "tf_apply_extra" {
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.registry_state_bucket}/aws/*"]
  }

  statement {
    sid       = "TerraformStateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.registry_state_bucket}"]
  }

  statement {
    sid     = "EKSManage"
    effect  = "Allow"
    actions = ["eks:*"]
    resources = [
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}",
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:nodegroup/${local.cluster_name}/*/*",
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:addon/${local.cluster_name}/*/*",
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:access-entry/${local.cluster_name}/*",
    ]
  }

  statement {
    sid       = "ReadOnlyDiscovery"
    effect    = "Allow"
    actions   = ["eks:Describe*", "eks:List*", "ec2:Describe*", "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTags"]
    resources = ["*"]
  }

  statement {
    sid       = "SubnetDiscoveryTags"
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:subnet/*"]
  }

  statement {
    sid    = "ClusterRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole", "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.cluster_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/homeease-tf-apply-eks-*",
    ]
  }

  statement {
    sid    = "NodeInstanceProfile"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${local.cluster_name}-*"]
  }

  statement {
    sid    = "ClusterOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.region}.amazonaws.com/id/*"]
  }

  # EKS validates that its service-linked roles exist using the CALLER's credentials
  statement {
    sid       = "ServiceLinkedRoleLookup"
    effect    = "Allow"
    actions   = ["iam:GetRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "elasticloadbalancing.amazonaws.com", "autoscaling.amazonaws.com"]
    }
  }

  statement {
    sid    = "CloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution", "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution", "cloudfront:ListDistributions",
      "cloudfront:TagResource", "cloudfront:UntagResource", "cloudfront:ListTagsForResource",
      "cloudfront:GetCachePolicy", "cloudfront:ListCachePolicies",
      "cloudfront:GetOriginRequestPolicy", "cloudfront:ListOriginRequestPolicies",
    ]
    resources = ["*"]
  }
}

module "tf_apply_role" {
  source = "../../modules/tf-apply-role"

  environment       = "eks-${var.environment}"
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = local.registry.oidc_provider_arn

  github_owner      = var.infra_github_owner
  github_repository = var.infra_github_repository
  allowed_branches  = ["main"]

  extra_policy_json = data.aws_iam_policy_document.tf_apply_extra.json

  tags = local.common_tags
}

# COST GUARDRAIL

resource "aws_budgets_budget" "monthly" {
  name         = "${local.cluster_name}-monthly"
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
