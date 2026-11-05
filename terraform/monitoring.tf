# --- Observability (Milestone 6) -----------------------------------------------------
#
#   backend pod --JSON log line--> Cloud Logging --log-based metric--> Cloud Monitoring
#                                                   gridpulse_http_5xx    |-> dashboard
#                                                                         '-> alert -> e-mail
#
# The backend writes ONE JSON log entry per request (backend/app/request_logging.py):
#   {"event": "http_request", "status_code": 500, "route": "/api/...", "probe": false,
#    "severity": "ERROR", "httpRequest": {...}, ...}

# 1. Log-based metric: counts user-facing HTTP 5xx responses -------------------------
# A counter (DELTA, INT64): every matching log entry adds 1, labelled with its
# status code, route template and method. Health-check probes (kubelet,
# load balancer, uptime check) are excluded with probe=false, so a pod that is
# still starting up cannot raise a false alarm.
resource "google_logging_metric" "http_5xx" {
  name        = "gridpulse_http_5xx"
  description = "User-facing HTTP 5xx responses served by the GridPulse backend, counted from its JSON request log (one entry per request; health-check probes excluded)."
  filter = join("\n", [
    "resource.type=\"k8s_container\"",
    "resource.labels.cluster_name=\"${google_container_cluster.main.name}\"",
    "resource.labels.namespace_name=\"gridpulse\"",
    "resource.labels.container_name=\"backend\"",
    "jsonPayload.event=\"http_request\"",
    "jsonPayload.probe=false",
    "jsonPayload.status_code>=500",
  ])

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "GridPulse HTTP 5xx responses"

    labels {
      key         = "status_code"
      value_type  = "INT64"
      description = "HTTP status code (500-599)"
    }
    labels {
      key         = "route"
      value_type  = "STRING"
      description = "FastAPI route template, e.g. /api/regions/{region_id}"
    }
    labels {
      key         = "method"
      value_type  = "STRING"
      description = "HTTP method"
    }
  }

  label_extractors = {
    status_code = "EXTRACT(jsonPayload.status_code)"
    route       = "EXTRACT(jsonPayload.route)"
    method      = "EXTRACT(jsonPayload.method)"
  }

  depends_on = [google_project_service.enabled]
}

# 2. Where notifications go -----------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.alert_emails)

  display_name = "GridPulse team - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }

  depends_on = [google_project_service.enabled]
}

locals {
  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.id]
}

# 3. Alert: too many server errors ----------------------------------------------------
resource "google_monitoring_alert_policy" "http_5xx" {
  display_name          = "GridPulse - HTTP 5xx errors"
  combiner              = "OR"
  severity              = "ERROR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "More than ${var.http_5xx_alert_threshold} user-facing HTTP 5xx responses within 5 minutes"
    condition_threshold {
      filter                  = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_5xx.name}\" AND resource.type=\"k8s_container\""
      comparison              = "COMPARISON_GT"
      threshold_value         = var.http_5xx_alert_threshold
      duration                = "60s"                              # the 5-min count must stay above the threshold for 1 min
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE" # no errors logged = no data = healthy (needs a non-zero duration)

      aggregations {
        alignment_period     = "300s" # rolling 5-minute window
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM" # all pods, routes and codes together
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    subject   = "GridPulse: HTTP 5xx errors on ${var.domain}"
    mime_type = "text/markdown"
    content   = <<-EOT
      The GridPulse backend returned more than ${var.http_5xx_alert_threshold} HTTP 5xx responses to users within 5 minutes.

      * Logs: Logs Explorer, query `resource.labels.container_name="backend" jsonPayload.event="http_request" jsonPayload.status_code>=500`
      * Stack traces: Error Reporting (service gridpulse-backend)
      * Dashboard: Monitoring > Dashboards > "GridPulse - production (Milestone 6)"
      * Live app: https://${var.domain}
    EOT
  }
}

# 4. Uptime check + alert: the site is unreachable over HTTPS ---------------------------
# Google probes https://<domain>/api/health/ready from several regions every
# minute - the full public path: DNS, load balancer, certificate, pod, database.
resource "google_monitoring_uptime_check_config" "https" {
  display_name = "GridPulse HTTPS - ${var.domain}"
  timeout      = "10s"
  period       = "60s"
  checker_type = "STATIC_IP_CHECKERS"

  http_check {
    path           = "/api/health/ready"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  content_matchers {
    content = "\"status\":\"ready\""
    matcher = "CONTAINS_STRING"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_monitoring_alert_policy" "uptime" {
  display_name          = "GridPulse - site unreachable over HTTPS"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.notification_channels

  conditions {
    display_name = "HTTPS uptime check failing from more than one region"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.https.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    subject   = "GridPulse: https://${var.domain} is not answering"
    mime_type = "text/markdown"
    content   = "The uptime check for https://${var.domain}/api/health/ready is failing from more than one region. Check `kubectl -n gridpulse get pods,ingress`, the managed certificate, and Cloud SQL."
  }
}

# 5. Alert: the pipeline rolled a release back ----------------------------------------
# .github/workflows/deploy.yml writes a structured entry to the
# "gridpulse-deployments" log after every deploy and every automatic rollback.
resource "google_monitoring_alert_policy" "rollback" {
  display_name          = "GridPulse - release rolled back by the pipeline"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = local.notification_channels

  conditions {
    display_name = "Automatic rollback logged by CI/CD"
    condition_matched_log {
      filter = "logName=\"projects/${var.project_id}/logs/gridpulse-deployments\" AND jsonPayload.event=\"rollback\""
      label_extractors = {
        failed_version   = "EXTRACT(jsonPayload.failed_version)"
        restored_version = "EXTRACT(jsonPayload.restored_version)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    subject   = "GridPulse: a release was rolled back automatically"
    mime_type = "text/markdown"
    content   = "The CI/CD pipeline deployed a release that failed its rollout or health check and restored the previous release. The GitHub Actions run summary has the details."
  }
}

# 6. Dashboard ---------------------------------------------------------------------------
# Error counts (the log-based metric + load balancer response classes), resource
# usage (CPU and memory per pod, replicas, restarts, Cloud SQL), latency, the
# uptime check, and a log panel with backend errors and pipeline deployments.
resource "google_monitoring_dashboard" "main" {
  dashboard_json = file("${path.module}/dashboards/gridpulse.json")

  depends_on = [google_logging_metric.http_5xx, google_monitoring_uptime_check_config.https]
}
