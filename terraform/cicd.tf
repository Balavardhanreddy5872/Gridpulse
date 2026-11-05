# --- CI/CD identity (Milestone 6) ----------------------------------------------------
# GitHub Actions gets Google credentials WITHOUT any key or secret stored in
# GitHub: Workload Identity Federation trusts GitHub's OIDC tokens, but only
# from this repository's deployment branch, and lets them act as one narrowly
# scoped service account for the duration of a pipeline run.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "OIDC tokens from GitHub Actions (GridPulse CI/CD)"

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.workflow"   = "assertion.workflow"
  }
  # Tokens from any other repository, or from any other branch of this one
  # (pull requests, feature branches), are rejected outright.
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/${var.deploy_branch}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci_deployer" {
  account_id   = "gridpulse-ci-deployer"
  display_name = "GridPulse CI/CD deployer"
  description  = "Used only by GitHub Actions (${var.github_repository}, ${var.deploy_branch}) via Workload Identity Federation. No keys."
}

# The pipeline of this repository (and only it) may act as the deployer.
resource "google_service_account_iam_member" "ci_deployer_from_github" {
  service_account_id = google_service_account.ci_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# What a deploy needs, and nothing else:
#   roles/artifactregistry.writer  push images - on the gridpulse repo only (registry.tf)
#   roles/container.developer      kubectl apply / rollout / rollout undo inside the
#                                  cluster (no IAM, no cluster settings, no RBAC)
#   roles/logging.logWriter        write a "deployed" / "rolled back" entry to Cloud
#                                  Logging (the rollback alert in monitoring.tf)
# It cannot read secrets, touch the database or bucket, or change any Google
# Cloud resource - that stays with Terraform and the team.
resource "google_project_iam_member" "ci_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = google_service_account.ci_deployer.member
}

resource "google_project_iam_member" "ci_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.ci_deployer.member
}
