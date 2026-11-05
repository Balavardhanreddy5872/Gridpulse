# --- Artifact Registry (Milestone 3) ---------------------------------------------
# One Docker repository for both images. The CI/CD pipeline pushes
# gridpulse-backend:<commit> and gridpulse-frontend:<commit> here.
resource "google_artifact_registry_repository" "images" {
  repository_id = "gridpulse"
  location      = var.region
  format        = "DOCKER"
  description   = "GridPulse container images"

  # Cost control from Milestone 3 (deploy/ar-cleanup-policy.json): untagged
  # layers are deleted after 7 days; the 5 newest versions are always kept.
  # Every release is tagged with its commit, so releases are never deleted.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "delete-untagged-after-7-days"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }
  cleanup_policies {
    id     = "always-keep-5-newest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  lifecycle {
    prevent_destroy = true
    # Google fills these in on its own; not something we configure.
    ignore_changes = [docker_config, vulnerability_scanning_config]
  }

  depends_on = [google_project_service.enabled]
}

# GKE nodes pull the images (Milestone 5) ...
resource "google_artifact_registry_repository_iam_member" "nodes_pull" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.gke_nodes.member
}

# ... and only the CI/CD pipeline pushes them (Milestone 6).
resource "google_artifact_registry_repository_iam_member" "ci_push" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.ci_deployer.member
}
