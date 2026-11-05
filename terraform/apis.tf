# Google APIs the application needs. Enabling an API that is already on is a
# no-op, so these need no import. disable_on_destroy is left at false: removing
# a resource here must never switch an API off under the running app.
locals {
  services = [
    "artifactregistry.googleapis.com",     # container images (M3)
    "cloudresourcemanager.googleapis.com", # project IAM
    "compute.googleapis.com",              # static IPs, VPC, load balancer
    "container.googleapis.com",            # GKE Autopilot (M5)
    "iam.googleapis.com",                  # service accounts
    "iamcredentials.googleapis.com",       # short-lived tokens (Workload Identity, CI/CD)
    "logging.googleapis.com",              # Cloud Logging + log-based metrics (M6)
    "monitoring.googleapis.com",           # dashboards, alerts, uptime checks (M6)
    "secretmanager.googleapis.com",        # DB password (M4)
    "servicenetworking.googleapis.com",    # Cloud SQL private IP peering (M4)
    "sqladmin.googleapis.com",             # Cloud SQL (M4)
    "storage.googleapis.com",              # uploads bucket (M4), Terraform state
    "sts.googleapis.com",                  # GitHub OIDC token exchange (M6)
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.services)

  project = var.project_id
  service = each.value
}
