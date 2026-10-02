# ============================================================
# Public ALB — two listeners, one per public-facing service, same
# port convention app_Homeease's docker-compose.yml already uses
# (8080 for frontend, 8081 for admin-frontend) so "which port is
# which app" stays one fact learned once, not re-learned per
# environment.
#
# HTTPS is opt-in: set certificate_arn (an ACM certificate in the same
# region, which needs a domain you control) and a 443 listener is
# added for frontend with HTTP :80 redirecting to it. With no
# certificate the ALB stays HTTP-only, a known dev limitation.
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

resource "aws_security_group" "alb" {
  name_prefix = "homeease-${var.environment}-alb-"
  description = "HomeEase ALB (${var.environment}) - public HTTP only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "sg-homeease-${var.environment}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name               = "homeease-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Fine for a dev/demo environment — no compliance requirement to
  # retain access logs here, and an S3 bucket + policy just to hold
  # them is real added surface for no current consumer.
  enable_deletion_protection = false

  tags = var.tags
}

resource "aws_lb_target_group" "frontend" {
  name        = "homeease-${var.environment}-frontend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for awsvpc-mode Fargate tasks

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_target_group" "admin_frontend" {
  name        = "homeease-${var.environment}-admin-frontend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.frontend.arn
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "frontend_https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "admin_frontend" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin_frontend.arn
  }
}

# ============================================================
# ALARMS — target health and 5xx per target group.
# ============================================================

locals {
  target_groups = {
    frontend       = aws_lb_target_group.frontend
    admin-frontend = aws_lb_target_group.admin_frontend
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = local.target_groups

  alarm_name          = "homeease-${var.environment}-${each.key}-unhealthy-hosts"
  alarm_description   = "${each.key} has unhealthy targets behind the ALB"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = each.value.arn_suffix
  }

  alarm_actions = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []
  ok_actions    = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = local.target_groups

  alarm_name          = "homeease-${var.environment}-${each.key}-5xx"
  alarm_description   = "${each.key} returned more than 10 5xx responses in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = each.value.arn_suffix
  }

  alarm_actions = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []
  ok_actions    = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []

  tags = var.tags
}
