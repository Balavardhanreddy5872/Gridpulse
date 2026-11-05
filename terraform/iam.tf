# --- Identities (Milestone 5, deploy/m5/01_cluster.sh + 02_workload_identity.sh) ---
# No service account below has a key. Nodes and pods get short-lived tokens
# from the GKE metadata server; the pipeline gets them from Workload Identity
# Federation (cicd.tf).

# What the GKE Autopilot NODES run as: write logs/metrics, pull images.
resource "google_service_account" "gke_nodes" {
  account_id   = "gridpulse-gke-nodes"
  display_name = "GridPulse GKE nodes"
  description  = "Identity of the GKE Autopilot nodes: logging, monitoring, image pulls. No keys."
}

resource "google_project_iam_member" "gke_nodes_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.gke_nodes.member
}

# What the backend PODS run as (Workload Identity): the Milestone 4
# least-privilege grants, each on the one resource it is for.
resource "google_service_account" "gke_app" {
  account_id   = "gridpulse-gke-app"
  display_name = "GridPulse backend on GKE"
  description  = "Identity of the backend pods (Workload Identity): Cloud SQL lookup, DB secret, upload bucket. No keys."
}

resource "google_project_iam_member" "gke_app_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client" # look up the instance's private IP
  member  = google_service_account.gke_app.member
}

# Only the Kubernetes service account gridpulse/gridpulse-backend
# (k8s/serviceaccount.yaml) may act as gridpulse-gke-app.
resource "google_service_account_iam_member" "gke_app_workload_identity" {
  service_account_id = google_service_account.gke_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[gridpulse/gridpulse-backend]"
}
