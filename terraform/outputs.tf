output "app_url" {
  value = "https://${var.domain}"
}

output "ingress_ip" {
  description = "The DuckDNS name must point here."
  value       = google_compute_global_address.ingress.address
}

output "cloudsql_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "workload_identity_provider" {
  description = "Goes into .github/workflows/deploy.yml (deploy/m6/03_wire_pipeline.sh does it)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account" {
  value = google_service_account.ci_deployer.email
}

output "log_based_metric" {
  value = "logging.googleapis.com/user/${google_logging_metric.http_5xx.name}"
}

output "dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.main.id), length(split("/", google_monitoring_dashboard.main.id)) - 1)}?project=${var.project_id}"
}

output "alert_policies" {
  value = {
    http_5xx = google_monitoring_alert_policy.http_5xx.name
    uptime   = google_monitoring_alert_policy.uptime.name
    rollback = google_monitoring_alert_policy.rollback.name
  }
}
