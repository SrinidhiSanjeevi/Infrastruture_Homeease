# ============================================================
# CloudFront in front of the public ALB — HTTPS with no domain.
#
# ACM will not issue a certificate for *.elb.amazonaws.com, so without a domain the ALB can only
# speak HTTP. Every CloudFront distribution gets a free <id>.cloudfront.net name that already
# carries a trusted AWS-managed certificate:
#
#   browser --HTTPS--> CloudFront --HTTP--> ALB (:80 frontend / :8081 admin) --> Fargate
#
# Viewer traffic is encrypted and HTTP is redirected to HTTPS. The CloudFront -> ALB hop stays on
# HTTP inside AWS (acceptable for dev; with a domain, use the ALB module's certificate_arn instead).
# Caching is disabled and everything is forwarded, so login, bookings and /api behave exactly as
# they do against the ALB directly.
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

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

locals {
  distributions = {
    app   = { origin_port = 80, comment = "HomeEase ${var.environment} customer app" }
    admin = { origin_port = 8081, comment = "HomeEase ${var.environment} admin console" }
  }
}

resource "aws_cloudfront_distribution" "this" {
  for_each = local.distributions

  enabled         = true
  is_ipv6_enabled = true
  comment         = each.value.comment
  price_class     = "PriceClass_200" # includes India; PriceClass_100 would route Indian users via Europe/US

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port                = each.value.origin_port
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 60
      origin_keepalive_timeout = 30
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}
