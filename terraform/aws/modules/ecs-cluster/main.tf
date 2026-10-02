# ============================================================
# ECS Cluster — Fargate only, no EC2 capacity to patch or size.
#
# Two capacity providers, weighted toward Spot: this is a dev/demo
# environment, and Fargate Spot is the same compute at roughly 70% off
# in exchange for a 2-minute interruption notice before reclaim. A
# stateless HTTP service behind an ALB, with ECS itself replacing an
# interrupted task automatically, tolerates that fine — same trade-off
# reasoning terraform/aws/modules/networking already applies to running
# one NAT Gateway instead of one per AZ. FARGATE (on-demand) stays as a
# fallback weight, not zero, so the cluster isn't 100% dependent on
# Spot capacity being available.
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

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  # Container Insights gives per-service CPU/memory/task-count graphs
  # in CloudWatch (the ECS counterpart of the Prometheus/Grafana stack
  # on AKS). It is billed per metric, so it stays switchable.
  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = var.spot_weight
    base              = 0
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.on_demand_weight
    base              = var.on_demand_base
  }
}

# ============================================================
# SERVICE CONNECT NAMESPACE
#
# The Fargate equivalent of Kubernetes Service DNS: backend.homeease
# resolves to whichever tasks are currently healthy, client-side
# load-balanced, no ALB hop for internal calls. This is what lets
# frontend's nginx proxy /api/ to "backend:5000" exactly like it
# already does inside the K8s cluster — same proxy_pass target,
# different DNS backing it.
# ============================================================

resource "aws_service_discovery_http_namespace" "this" {
  name = var.namespace_name

  tags = var.tags
}
