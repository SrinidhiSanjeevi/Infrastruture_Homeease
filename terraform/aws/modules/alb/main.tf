# ============================================================
# Public ALB — two listeners, one per public-facing service, same
# port convention app_Homeease's docker-compose.yml already uses
# (8080 for frontend, 8081 for admin-frontend) so "which port is
# which app" stays one fact learned once, not re-learned per
# environment.
#
# No HTTPS listener: no ACM certificate exists yet, matching
# platform/README.md's own honesty on the Kubernetes side that
# cert-manager is a placeholder, not installed. HTTP-only is the
# correct state to represent that here too, not a gap unique to this
# stack.
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
