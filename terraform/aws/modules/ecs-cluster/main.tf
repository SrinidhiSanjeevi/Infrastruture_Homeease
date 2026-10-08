# ECS Cluster — Fargate only, no EC2 capacity to patch or size.

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

  # Container Insights gives per-service CPU/memory/task-count graphs in CloudWatch
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

# SERVICE CONNECT NAMESPACE

resource "aws_service_discovery_http_namespace" "this" {
  name = var.namespace_name

  tags = var.tags
}
