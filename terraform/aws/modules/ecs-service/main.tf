# ============================================================
# One Fargate service — task definition, service, own security group,
# own CloudWatch log group, own autoscaling target. Instantiated once
# per HomeEase service in environments/fargate-dev/main.tf, the same
# way charts/<service>/ is one Helm chart per service in gitops_homeease.
#
# No container-level healthCheck override here on purpose: every image
# already ships a Docker HEALTHCHECK instruction (wget against
# /health/live or /health) from app_Homeease's Dockerfiles — ECS
# Fargate reads that natively. The same healthcheck that already works
# under docker-compose works here unchanged.
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

# ============================================================
# SECURITY GROUP — mirrors the exact allow-list each
# charts/<service>/templates/networkpolicy.yaml already encodes:
# ingress from specific named sources only, no default-allow. Egress
# stays unrestricted, same reasoning as every NetworkPolicy's own
# "No egress block" comment (Mongo, payment-service, Razorpay, and for
# public services, nothing egress-restricted can reach that isn't
# already an outbound call the app makes today).
# ============================================================

resource "aws_security_group" "this" {
  name_prefix = "homeease-${var.environment}-${var.name}-"
  description = "HomeEase ${var.name} (${var.environment}) — ingress scoped to its real callers only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "sg-homeease-${var.environment}-${var.name}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "from_alb" {
  count = var.alb_security_group_id != null ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = var.alb_security_group_id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  description              = "ALB -> ${var.name}"
}

resource "aws_security_group_rule" "from_peers" {
  for_each = var.allowed_source_security_group_ids

  type                     = "ingress"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = each.value
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  description              = "peer service -> ${var.name}"
}

# ============================================================
# LOGGING
# ============================================================

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/homeease-${var.environment}/${var.name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ============================================================
# TASK DEFINITION
# ============================================================

resource "aws_ecs_task_definition" "this" {
  family                   = "homeease-${var.environment}-${var.name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true

      portMappings = [
        {
          name          = "http"
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      secrets = [
        for k, arn in var.secrets : { name = k, valueFrom = arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = var.name
        }
      }
    }
  ])

  tags = var.tags
}

data "aws_region" "current" {}

# ============================================================
# SERVICE
# ============================================================

resource "aws_ecs_service" "this" {
  name            = "homeease-${var.environment}-${var.name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = var.spot_weight
    base              = 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.on_demand_weight
    base              = var.on_demand_base
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.alb_target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    service {
      port_name      = "http"
      discovery_name = var.name
      client_alias {
        port = var.container_port
      }
    }
  }

  # ECS's own default MinimumHealthyPercent/MaximumPercent (100/200)
  # already gives a rolling deploy with no downtime — explicit here so
  # it's a decision, not an unstated default, matching the PDB
  # maxUnavailable comment's own style on the Kubernetes side.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  tags = var.tags

  lifecycle {
    ignore_changes = [desired_count] # autoscaling owns this after first apply
  }
}

# ============================================================
# AUTOSCALING — target tracking on CPU, same 70% target and the same
# min/max shape as this service's HPA in gitops_homeease
# (charts/<service>/values.yaml's hpa: block). Not a coincidence:
# same workload, same load characteristics, same threshold.
# ============================================================

resource "aws_appautoscaling_target" "this" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "homeease-${var.environment}-${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
