# ============================================================
# HomeEase EKS cluster — mirrors terraform/azure/modules/aks: managed
# control plane, one auto-scaling node group, OIDC issuer enabled for
# workload identity (IRSA here, Azure Workload Identity there), and
# NetworkPolicy enforcement turned on so apps/*/base/networkpolicy.yaml
# in gitops_homeease is actually enforced, not just accepted by the API.
# ============================================================

# ============================================================
# CLUSTER IAM ROLE
# ============================================================

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ============================================================
# CLUSTER
# ============================================================

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # API-only auth (no aws-auth ConfigMap to hand-edit) — whoever runs
  # `terraform apply` gets cluster-admin automatically via
  # bootstrap_cluster_creator_admin_permissions. Grant anyone else
  # access with `aws eks create-access-entry` afterwards, not by
  # editing a ConfigMap.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = var.tags
}

# ============================================================
# OIDC PROVIDER — for IRSA (IAM Roles for Service Accounts).
#
# This is a SEPARATE OIDC provider from the GitHub Actions one in
# modules/ci-oidc — that one authenticates GitHub Actions workflows to
# AWS; this one authenticates Kubernetes ServiceAccounts (running
# inside THIS cluster) to AWS. Same mechanism (OIDC federation), two
# completely different issuers and audiences.
# ============================================================

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ============================================================
# NODE IAM ROLE
#
# Deliberately NOT attached: AmazonEC2ContainerRegistryReadOnly. Image
# pulls are instead authorized by the ecr module's per-repository
# policy (pull_principal_arns, set to this role's ARN in
# environments/dev/main.tf) — scoped to exactly the 4 homeease
# repositories, not every ECR repository in the account. Same
# least-privilege discipline the ecr and ci-oidc modules already use.
# ============================================================

data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Session Manager access to nodes without SSH keys or an open
# security-group port 22 — same "no long-lived credentials, no extra
# attack surface" spirit as the OIDC-only CI roles elsewhere in this
# repo.
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-node"
  role = aws_iam_role.node.name
}

# ============================================================
# NODE GROUP — auto-scaling, private subnets only. min/max 1-3 mirrors
# the AKS default_node_pool's auto_scaling_enabled range.
# ============================================================

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # The AWS provider has no implicit dependency between a node group
  # and the IAM policy attachments its role needs — without this,
  # `terraform apply` can try to launch nodes before the role can
  # actually do anything, and they fail to join the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ssm,
  ]

  tags = var.tags
}

# ============================================================
# CORE ADDONS
#
# vpc-cni's ENABLE_NETWORK_POLICY is the AWS-side equivalent of AKS's
# network_policy = "azure" — without it, apps/*/base/networkpolicy.yaml
# in gitops_homeease is accepted by the API but never enforced (see the
# comment in that file).
# ============================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  configuration_values = var.enable_network_policy ? jsonencode({
    env = { ENABLE_NETWORK_POLICY = "true" }
  }) : null

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS pods need a schedulable node to become healthy.
  depends_on = [aws_eks_node_group.default]

  tags = var.tags
}
