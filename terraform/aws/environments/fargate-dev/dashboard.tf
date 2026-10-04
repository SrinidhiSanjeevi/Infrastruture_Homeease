# ============================================================
# CloudWatch dashboards — the AWS counterpart of the four Grafana
# dashboards on AKS (gitops_homeease/platform/kube-prometheus-stack/
# dashboards): Business Overview, Payment Service, RED & infrastructure,
# Logs.
#
# Where each number comes from:
#
#  * Business and payment numbers: MongoDB is the source of truth. The
#    backend and payment-service read the counts from the database every
#    30 s and publish them (namespace "HomeEase"). Every pod publishes the
#    same value, so widgets use Maximum (never Sum) and a restart loses
#    nothing — the same "max()" rule the Grafana panels use.
#  * Traffic, latency, errors, CPU, memory, task counts: the ALB, ECS and
#    Container Insights publish these natively.
#  * Logs: CloudWatch Logs Insights queries over the six service log groups.
#
# Not carried over (nothing on AWS produces the data): DORA (comes from the
# Azure pipeline) and Prometheus request-latency histograms.
# ============================================================

locals {
  cw_region = var.region
  cluster   = local.resource_prefix # homeease-dev

  # service key -> display name, in the order Grafana lists them
  svc_names = {
    "backend"              = "Backend API"
    "admin-backend"        = "Admin Backend"
    "payment-service"      = "Payment Service"
    "notification-service" = "Notification Service"
    "frontend"             = "Frontend"
    "admin-frontend"       = "Admin Frontend"
  }

  booking_statuses = ["Created", "Assigned", "Confirmed", "Completed", "Cancelled"]
  payment_statuses = ["Pending", "Success", "Failure", "Refunded", "Partially Refunded"]

  log_groups = [for k, _ in local.svc_names : "/ecs/${local.cluster}/${k}"]
  log_source = join(" | ", [for g in local.log_groups : "SOURCE '${g}'"])

  # --- metric helpers --------------------------------------------------------
  total_metric = { for n in ["TotalBookings", "TotalUsers", "TotalServices", "TotalProfessionals", "AvailableProfessionals", "TotalEmergencies", "ActiveEmergencies", "Revenue", "PendingBookings"] : n => ["HomeEase", n, "Scope", "totals"] }
  booking_m    = { for s in local.booking_statuses : s => ["HomeEase", "Bookings", "Scope", "bookings", "Status", s] }
  pay_count_m  = { for s in local.payment_statuses : s => ["HomeEase", "PaymentRecords", "Scope", "payments", "Status", s] }
  pay_amount_m = { for s in local.payment_statuses : s => ["HomeEase", "PaymentAmount", "Scope", "payments", "Status", s] }

  running_m = { for k, _ in local.svc_names : k => ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}"] }
}


# ------------------------------------------------------------------
# Traffic / latency panels (the Prometheus http_* panels in Grafana).
# Computed from the one-line-per-request logs the services write, so no
# extra agent or cost: request rate, 4xx/5xx, p50/p95/p99 latency.
# ------------------------------------------------------------------
locals {
  api_services = ["backend", "admin-backend", "payment-service", "notification-service"]
  api_source   = join(" | ", [for k in local.api_services : "SOURCE '/ecs/${local.cluster}/${k}'"])
  req          = "filter msg = \"request completed\" and req.url not like /health/ and req.url not like /metrics/"

  business_extra = [
    {
      type = "log", x = 0, y = 24, width = 12, height = 6
      properties = {
        title   = "Booking Request Rate (new bookings requested, per 5 min)"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "SOURCE '/ecs/${local.cluster}/backend' | filter msg = \"request completed\" and req.method = \"POST\" and req.url = \"/api/bookings\" | stats count(*) as booking_requests by bin(5m)"
      }
    },
    {
      type = "log", x = 12, y = 24, width = 12, height = 6
      properties = {
        title   = "Backend API latency p50 / p95 (ms)"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "SOURCE '/ecs/${local.cluster}/backend' | ${local.req} | stats pct(responseTime, 50) as p50_ms, pct(responseTime, 95) as p95_ms by bin(5m)"
      }
    },
  ]

  payments_extra = [
    {
      type = "log", x = 0, y = 23, width = 8, height = 6
      properties = {
        title   = "HTTP Request Rate (payment-service, per 5 min)"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "SOURCE '/ecs/${local.cluster}/payment-service' | ${local.req} | stats count(*) as requests by bin(5m)"
      }
    },
    {
      type = "log", x = 8, y = 23, width = 8, height = 6
      properties = {
        title   = "HTTP 5xx Errors (payment-service)"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "SOURCE '/ecs/${local.cluster}/payment-service' | filter msg = \"request completed\" and res.statusCode >= 500 | stats count(*) as errors_5xx by bin(5m)"
      }
    },
    {
      type = "log", x = 16, y = 23, width = 8, height = 6
      properties = {
        title   = "Payment Latency p50 / p95 / p99 (HTTP, ms)"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "SOURCE '/ecs/${local.cluster}/payment-service' | ${local.req} | stats pct(responseTime, 50) as p50_ms, pct(responseTime, 95) as p95_ms, pct(responseTime, 99) as p99_ms by bin(5m)"
      }
    },
  ]

  ecs_extra = [
    {
      type       = "text", x = 0, y = 24, width = 24, height = 1
      properties = { markdown = "### Per-service traffic (from request logs)" }
    },
    {
      type = "log", x = 0, y = 25, width = 8, height = 6
      properties = {
        title   = "Requests per 5 min, by service"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = true
        query   = "${local.api_source} | ${local.req} | stats count(*) as requests by bin(5m), service"
      }
    },
    {
      type = "log", x = 8, y = 25, width = 8, height = 6
      properties = {
        title   = "5xx errors per 5 min, by service"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = true
        query   = "${local.api_source} | filter msg = \"request completed\" and res.statusCode >= 500 | stats count(*) as errors_5xx by bin(5m), service"
      }
    },
    {
      type = "log", x = 16, y = 25, width = 8, height = 6
      properties = {
        title   = "Latency p95 (ms), by service"
        region  = local.cw_region
        view    = "timeSeries"
        stacked = false
        query   = "${local.api_source} | ${local.req} | stats pct(responseTime, 95) as p95_ms by bin(5m), service"
      }
    },
    {
      type = "log", x = 0, y = 31, width = 12, height = 7
      properties = {
        title  = "RED summary by service (whole time range)"
        region = local.cw_region
        view   = "table"
        query  = "${local.api_source} | ${local.req} | stats count(*) as requests, pct(responseTime, 50) as p50_ms, pct(responseTime, 95) as p95_ms, pct(responseTime, 99) as p99_ms, sum(res.statusCode >= 500) as errors_5xx, sum(res.statusCode >= 400 and res.statusCode < 500) as errors_4xx by service"
      }
    },
    {
      type = "log", x = 12, y = 31, width = 12, height = 7
      properties = {
        title  = "Slowest endpoints (p95 ms)"
        region = local.cw_region
        view   = "table"
        query  = "${local.api_source} | ${local.req} | parse req.url /^\\/(?<seg1>[^\\/?]+)\\/(?<seg2>[^\\/?]+)/ | stats count(*) as hits, pct(responseTime, 95) as p95_ms by seg1, seg2, req.method | sort p95_ms desc | limit 10"
      }
    },
  ]
}

# ============================================================
# 1. BUSINESS OVERVIEW  (Grafana: "HomeEase Business Overview")
# ============================================================
resource "aws_cloudwatch_dashboard" "business" {
  dashboard_name = "${local.cluster}-business-overview"

  dashboard_body = jsonencode({
    widgets = concat([
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# HomeEase Business Overview (${var.environment})\nEvery number below is read from **MongoDB** (the source of truth) and published by the backend every 30 s. Two pods publish the same value, so a pod restart changes nothing."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 24, height = 4
        properties = {
          title = "Bookings", view = "singleValue", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [
            concat(local.total_metric["TotalBookings"], [{ label = "Total Bookings" }]),
            concat(local.booking_m["Completed"], [{ label = "Completed" }]),
            concat(local.booking_m["Confirmed"], [{ label = "Confirmed" }]),
            concat(local.booking_m["Cancelled"], [{ label = "Cancelled" }]),
            [{ expression = "m1+m2+m3", label = "Active (Created+Assigned+Confirmed)", id = "e1" }],
            concat(local.booking_m["Created"], [{ id = "m1", visible = false }]),
            concat(local.booking_m["Assigned"], [{ id = "m2", visible = false }]),
            concat(local.booking_m["Confirmed"], [{ id = "m3", visible = false }]),
            concat(local.booking_m["Assigned"], [{ label = "Awaiting a professional (Assigned)", id = "m4" }]),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 24, height = 4
        properties = {
          title = "People, services, money", view = "singleValue", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [
            concat(local.total_metric["Revenue"], [{ label = "Total Revenue (₹)" }]),
            concat(local.total_metric["TotalUsers"], [{ label = "Total Users" }]),
            concat(local.total_metric["TotalProfessionals"], [{ label = "Total Professionals" }]),
            concat(local.total_metric["AvailableProfessionals"], [{ label = "Available Professionals" }]),
            concat(local.total_metric["TotalServices"], [{ label = "Total Services" }]),
            concat(local.total_metric["TotalEmergencies"], [{ label = "Emergency Requests" }]),
            concat(local.total_metric["ActiveEmergencies"], [{ label = "Active Emergencies" }]),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 10, width = 6, height = 5
        properties = {
          title = "Booking Confirmation Rate (all bookings)", view = "gauge", region = local.cw_region, stat = "Maximum", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "IF(m3>0, 100*(m1+m2)/m3, 0)", label = "Confirmation %", id = "e1" }],
            concat(local.booking_m["Confirmed"], [{ id = "m1", visible = false }]),
            concat(local.booking_m["Completed"], [{ id = "m2", visible = false }]),
            concat(local.total_metric["TotalBookings"], [{ id = "m3", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 6, y = 10, width = 6, height = 5
        properties = {
          title = "Booking Cancellation Rate (all bookings)", view = "gauge", region = local.cw_region, stat = "Maximum", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "IF(m2>0, 100*m1/m2, 0)", label = "Cancellation %", id = "e1" }],
            concat(local.booking_m["Cancelled"], [{ id = "m1", visible = false }]),
            concat(local.total_metric["TotalBookings"], [{ id = "m2", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 12, y = 10, width = 6, height = 5
        properties = {
          title = "Booking Completion Rate (confirmed bookings)", view = "gauge", region = local.cw_region, stat = "Maximum", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "IF((m1+m2)>0, 100*m1/(m1+m2), 0)", label = "Completion %", id = "e1" }],
            concat(local.booking_m["Completed"], [{ id = "m1", visible = false }]),
            concat(local.booking_m["Confirmed"], [{ id = "m2", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 18, y = 10, width = 6, height = 5
        properties = {
          title = "Service Availability % (services with a running task)", view = "gauge", region = local.cw_region, stat = "Minimum", period = 60
          yAxis = { left = { min = 0, max = 100 } }
          metrics = concat(
            [[{ expression = "100*(IF(m1>0,1,0)+IF(m2>0,1,0)+IF(m3>0,1,0)+IF(m4>0,1,0)+IF(m5>0,1,0)+IF(m6>0,1,0))/6", label = "Availability %", id = "e1" }]],
            [for i, k in keys(local.svc_names) : concat(local.running_m[k], [{ id = "m${i + 1}", visible = false }])]
          )
        }
      },
      {
        type = "metric", x = 0, y = 15, width = 24, height = 3
        properties = {
          title   = "Service status (running tasks; 1 = up, 0 = down)", view = "singleValue", region = local.cw_region, stat = "Minimum", period = 60
          metrics = [for k, name in local.svc_names : concat(local.running_m[k], [{ label = name }])]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title   = "Bookings by status (over time)", view = "timeSeries", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [for s in local.booking_statuses : concat(local.booking_m[s], [{ label = s }])]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6
        properties = {
          title = "Pending (Created + Assigned) and active emergencies", view = "timeSeries", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [
            concat(local.total_metric["PendingBookings"], [{ label = "Pending bookings" }]),
            concat(local.total_metric["ActiveEmergencies"], [{ label = "Active emergencies" }]),
          ]
        }
      },
    ], local.business_extra)
  })
}

# ============================================================
# 2. PAYMENT SERVICE  (Grafana: "HomeEase - Payment Service")
# ============================================================
resource "aws_cloudwatch_dashboard" "payments" {
  dashboard_name = "${local.cluster}-payment-service"

  dashboard_body = jsonencode({
    widgets = concat([
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# HomeEase Payment Service (${var.environment})\nPayment records and amounts are read from the **payment database** by payment-service every 30 s. They are true all-time totals, not counts since a pod started."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 24, height = 4
        properties = {
          title = "Payments (all time)", view = "singleValue", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [
            [{ expression = "m1+m2+m3+m4+m5", label = "Total Payments", id = "e1" }],
            [{ expression = "m4+m5", label = "Refunds (full + partial)", id = "e2" }],
            concat(local.pay_count_m["Pending"], [{ id = "m1", visible = false }]),
            concat(local.pay_count_m["Success"], [{ label = "Successful Payments", id = "m2" }]),
            concat(local.pay_count_m["Failure"], [{ label = "Failed Payments", id = "m3" }]),
            concat(local.pay_count_m["Refunded"], [{ id = "m4", visible = false }]),
            concat(local.pay_count_m["Partially Refunded"], [{ id = "m5", visible = false }]),
            concat(local.pay_amount_m["Success"], [{ label = "Revenue Collected (₹)", id = "a1" }]),
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 6, height = 5
        properties = {
          title = "Payment Success Rate (all time)", view = "gauge", region = local.cw_region, stat = "Maximum", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "IF((m1+m2)>0, 100*m1/(m1+m2), 0)", label = "Success %", id = "e1" }],
            concat(local.pay_count_m["Success"], [{ id = "m1", visible = false }]),
            concat(local.pay_count_m["Failure"], [{ id = "m2", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 6, y = 6, width = 6, height = 5
        properties = {
          title = "Payment Failure Rate (all time)", view = "gauge", region = local.cw_region, stat = "Maximum", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "IF((m1+m2)>0, 100*m2/(m1+m2), 0)", label = "Failure %", id = "e1" }],
            concat(local.pay_count_m["Success"], [{ id = "m1", visible = false }]),
            concat(local.pay_count_m["Failure"], [{ id = "m2", visible = false }]),
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 5
        properties = {
          title = "Payment Service status", view = "singleValue", region = local.cw_region, stat = "Minimum", period = 60
          metrics = [
            concat(local.running_m["payment-service"], [{ label = "Running tasks (1 = up)" }]),
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-payment-service", { label = "CPU %", stat = "Average" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-payment-service", { label = "Memory %", stat = "Average" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 11, width = 12, height = 6
        properties = {
          title   = "Payments by status (over time)", view = "timeSeries", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [for s in local.payment_statuses : concat(local.pay_count_m[s], [{ label = s }])]
        }
      },
      {
        type = "metric", x = 12, y = 11, width = 12, height = 6
        properties = {
          title   = "Amount by status (₹, over time)", view = "timeSeries", region = local.cw_region, stat = "Maximum", period = 60
          metrics = [for s in local.payment_statuses : concat(local.pay_amount_m[s], [{ label = s }])]
        }
      },
      {
        type = "log", x = 0, y = 17, width = 24, height = 6
        properties = {
          title  = "Payment events: webhooks, failures, refunds"
          region = local.cw_region
          view   = "table"
          query  = "SOURCE '/ecs/${local.cluster}/payment-service' | fields @timestamp, msg, err | filter @message like /(?i)webhook|payment.failed|refund|signature/ | sort @timestamp desc | limit 50"
        }
      },
    ], local.payments_extra)
  })
}

# ============================================================
# 3. RED & INFRASTRUCTURE  (Grafana: "HomeEase RED & Kubernetes")
#    Rate (requests), Errors (5xx), Duration (latency) + tasks/CPU/memory
# ============================================================
resource "aws_cloudwatch_dashboard" "ecs" {
  dashboard_name = "${local.cluster}-red-ecs"

  dashboard_body = jsonencode({
    widgets = concat([
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# HomeEase RED & ECS (${var.environment})\n**R**ate, **E**rrors and **D**uration come from the load balancer; tasks, CPU and memory come from ECS / Container Insights."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 12, height = 4
        properties = {
          title   = "Running tasks by service", view = "singleValue", region = local.cw_region, stat = "Minimum", period = 60
          metrics = [for k, name in local.svc_names : concat(local.running_m[k], [{ label = name }])]
        }
      },
      {
        type = "metric", x = 12, y = 2, width = 12, height = 4
        properties = {
          title = "Healthy / unhealthy targets behind the ALB", view = "singleValue", region = local.cw_region, stat = "Minimum", period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", module.alb.frontend_tg_arn_suffix, "LoadBalancer", module.alb.arn_suffix, { label = "Frontend healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", module.alb.frontend_tg_arn_suffix, "LoadBalancer", module.alb.arn_suffix, { label = "Frontend unhealthy", stat = "Maximum" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", module.alb.admin_frontend_tg_arn_suffix, "LoadBalancer", module.alb.arn_suffix, { label = "Admin healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", module.alb.admin_frontend_tg_arn_suffix, "LoadBalancer", module.alb.arn_suffix, { label = "Admin unhealthy", stat = "Maximum" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title   = "Rate: requests per minute", view = "timeSeries", region = local.cw_region, stat = "Sum", period = 60
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.arn_suffix, { label = "Requests" }]]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title = "Errors: responses by class", view = "timeSeries", region = local.cw_region, stat = "Sum", period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "2xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "4xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "5xx (app)" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "5xx (ALB)" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 6, width = 8, height = 6
        properties = {
          title = "Duration: response time (seconds)", view = "timeSeries", region = local.cw_region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p50", stat = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p95", stat = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p99", stat = "p99" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title   = "CPU % by service", view = "timeSeries", region = local.cw_region, stat = "Average", period = 60
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [for k, name in local.svc_names : ["AWS/ECS", "CPUUtilization", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}", { label = name }]]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title   = "Memory % by service", view = "timeSeries", region = local.cw_region, stat = "Average", period = 60
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [for k, name in local.svc_names : ["AWS/ECS", "MemoryUtilization", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}", { label = name }]]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title   = "Memory used by service (MB)", view = "bar", region = local.cw_region, stat = "Average", period = 300
          metrics = [for k, name in local.svc_names : ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}", { label = name }]]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6
        properties = {
          title = "Desired vs running tasks", view = "timeSeries", region = local.cw_region, stat = "Average", period = 60
          metrics = concat(
            [for k, name in local.svc_names : ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}", { label = "${name} desired" }]],
            [for k, name in local.svc_names : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster, "ServiceName", "${local.cluster}-${k}", { label = "${name} running" }]]
          )
        }
      },
    ], local.ecs_extra)
  })
}

# ============================================================
# 4. LOGS  (Grafana: "HomeEase - Logs (Alloy → Loki)")
#    CloudWatch Logs Insights over the six service log groups.
# ============================================================
resource "aws_cloudwatch_dashboard" "logs" {
  dashboard_name = "${local.cluster}-logs"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "log", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Log volume by service (lines / 5 min)"
          region  = local.cw_region
          view    = "timeSeries"
          stacked = true
          query   = "${local.log_source} | filter ispresent(@message) | stats count(*) as lines by bin(5m), @log"
        }
      },
      {
        type = "log", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Errors by service (level 50+, lines / 5 min)"
          region  = local.cw_region
          view    = "timeSeries"
          stacked = true
          query   = "${local.log_source} | filter level >= 50 | stats count(*) as errors by bin(5m), @log"
        }
      },
      {
        type = "log", x = 0, y = 6, width = 24, height = 7
        properties = {
          title  = "Application errors (live)"
          region = local.cw_region
          view   = "table"
          query  = "${local.log_source} | fields @timestamp, service, msg, err | filter level >= 50 | sort @timestamp desc | limit 50"
        }
      },
      {
        type = "log", x = 0, y = 13, width = 12, height = 7
        properties = {
          title  = "Payment events: webhooks, failures, refunds"
          region = local.cw_region
          view   = "table"
          query  = "SOURCE '/ecs/${local.cluster}/payment-service' | fields @timestamp, msg, err | filter @message like /(?i)webhook|payment.failed|refund|signature/ | sort @timestamp desc | limit 50"
        }
      },
      {
        type = "log", x = 12, y = 13, width = 12, height = 7
        properties = {
          title  = "Notification service (emails)"
          region = local.cw_region
          view   = "table"
          query  = "SOURCE '/ecs/${local.cluster}/notification-service' | fields @timestamp, msg, err | sort @timestamp desc | limit 50"
        }
      },
      {
        type = "log", x = 0, y = 20, width = 24, height = 8
        properties = {
          title  = "All HomeEase logs (latest)"
          region = local.cw_region
          view   = "table"
          query  = "${local.log_source} | fields @timestamp, @log, msg | filter ispresent(msg) | sort @timestamp desc | limit 100"
        }
      },
    ]
  })
}
