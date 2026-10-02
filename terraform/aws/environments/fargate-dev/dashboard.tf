# ============================================================
# CloudWatch dashboard — the AWS counterpart of the Grafana boards.
#
# Two kinds of numbers, from two different sources on purpose:
#
#  1. BUSINESS STATE (bookings by status, pending, users, revenue):
#     MongoDB is the single source of truth. The backend's metrics
#     collector reads the counts from the database and publishes them
#     (HomeEase namespace). Every pod publishes the same number, so
#     losing a pod loses nothing; widgets use the Maximum statistic,
#     never Sum, so two pods are not double counted.
#
#  2. TRAFFIC / HEALTH (requests, errors, latency, CPU, memory, task
#     count): the ALB and ECS publish these natively; no app code.
# ============================================================

locals {
  dashboard_services = ["backend", "admin-backend", "payment-service", "notification-service", "frontend", "admin-frontend"]
  booking_statuses   = ["Created", "Assigned", "Confirmed", "Completed", "Cancelled"]
  region             = var.region
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.resource_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "## HomeEase (${var.environment})\n**Business numbers** come from MongoDB (source of truth), published by the backend; they survive any pod restart. **Traffic and health** come from the ALB and ECS."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 24, height = 4
        properties = {
          title  = "Business now (from the database)"
          view   = "singleValue"
          region = local.region
          stat   = "Maximum"
          period = 60
          metrics = [
            for m in ["PendingBookings", "TotalBookings", "TotalUsers", "TotalProfessionals", "AvailableProfessionals", "ActiveEmergencies", "Revenue"] :
            ["HomeEase", m, "Scope", "totals"]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Bookings by status"
          view   = "timeSeries"
          region = local.region
          stat   = "Maximum"
          period = 60
          metrics = [
            for s in local.booking_statuses :
            ["HomeEase", "Bookings", "Scope", "bookings", "Status", s]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Pending (Created + Assigned) and active emergencies"
          view   = "timeSeries"
          region = local.region
          stat   = "Maximum"
          period = 60
          metrics = [
            ["HomeEase", "PendingBookings", "Scope", "totals"],
            ["HomeEase", "ActiveEmergencies", "Scope", "totals"]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 8, height = 6
        properties = {
          title  = "ALB requests"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 8, y = 12, width = 8, height = 6
        properties = {
          title  = "Errors (5xx)"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 16, y = 12, width = 8, height = 6
        properties = {
          title  = "Response time (p95, seconds)"
          view   = "timeSeries"
          region = local.region
          stat   = "p95"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 8, height = 6
        properties = {
          title  = "CPU % by service"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            for s in local.dashboard_services :
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.resource_prefix, "ServiceName", "${local.resource_prefix}-${s}"]
          ]
        }
      },
      {
        type = "metric", x = 8, y = 18, width = 8, height = 6
        properties = {
          title  = "Memory % by service"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            for s in local.dashboard_services :
            ["AWS/ECS", "MemoryUtilization", "ClusterName", local.resource_prefix, "ServiceName", "${local.resource_prefix}-${s}"]
          ]
        }
      },
      {
        type = "metric", x = 16, y = 18, width = 8, height = 6
        properties = {
          title  = "Running tasks by service (Container Insights)"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            for s in local.dashboard_services :
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.resource_prefix, "ServiceName", "${local.resource_prefix}-${s}"]
          ]
        }
      }
    ]
  })
}
