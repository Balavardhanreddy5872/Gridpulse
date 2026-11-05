# Adopting what Milestones 3-5 created with gcloud (deploy/m4/*.sh, deploy/m5/*.sh).
#
# On the first `terraform plan` each block below says "will be imported": Terraform
# reads the live resource into its state instead of creating a new one. After the
# first `terraform apply` they are already in the state and these blocks do nothing
# (kept as a record of where each resource came from). Google APIs need no import:
# enabling an enabled API is a no-op (apis.tf).
locals {
  p          = var.project_id
  app_sa     = "gridpulse-gke-app@${var.project_id}.iam.gserviceaccount.com"
  nodes_sa   = "gridpulse-gke-nodes@${var.project_id}.iam.gserviceaccount.com"
  repository = "projects/${var.project_id}/locations/${var.region}/repositories/gridpulse"
}

# --- network (M4 private services access, M5 load balancer IP) ----------------------
import {
  to = google_compute_global_address.cloudsql_private_range
  id = "projects/${local.p}/global/addresses/gridpulse-psa-range"
}
import {
  to = google_service_networking_connection.cloudsql_peering
  id = "projects/${local.p}/global/networks/default:servicenetworking.googleapis.com"
}
import {
  to = google_compute_global_address.ingress
  id = "projects/${local.p}/global/addresses/gridpulse-gke-ip"
}

# --- Artifact Registry (M3) ------------------------------------------------------------
import {
  to = google_artifact_registry_repository.images
  id = local.repository
}
import {
  to = google_artifact_registry_repository_iam_member.nodes_pull
  id = "${local.repository} roles/artifactregistry.reader serviceAccount:${local.nodes_sa}"
}

# --- Cloud SQL (M4) --------------------------------------------------------------------
import {
  to = google_sql_database_instance.main
  id = "projects/${local.p}/instances/gridpulse-db"
}
import {
  to = google_sql_database.app
  id = "projects/${local.p}/instances/gridpulse-db/databases/gridpulse"
}
import {
  to = google_sql_user.app
  id = "${local.p}/gridpulse-db/gridpulse"
}

# --- Secret Manager (M4) - the secrets, never their values ----------------------------
import {
  to = google_secret_manager_secret.db_password
  id = "projects/${local.p}/secrets/gridpulse-db-password"
}
import {
  to = google_secret_manager_secret.db_root_password
  id = "projects/${local.p}/secrets/gridpulse-db-root-password"
}
import {
  to = google_secret_manager_secret_iam_member.app_reads_db_password
  id = "projects/${local.p}/secrets/gridpulse-db-password roles/secretmanager.secretAccessor serviceAccount:${local.app_sa}"
}

# --- Cloud Storage (M4) ----------------------------------------------------------------
import {
  to = google_storage_bucket.uploads
  id = "${local.p}-uploads"
}
import {
  to = google_storage_bucket_iam_member.app_uploads
  id = "b/${local.p}-uploads roles/storage.objectCreator serviceAccount:${local.app_sa}"
}
import {
  to = google_storage_bucket_iam_member.app_reads
  id = "b/${local.p}-uploads roles/storage.objectViewer serviceAccount:${local.app_sa}"
}

# --- identities (M5) -------------------------------------------------------------------
import {
  to = google_service_account.gke_nodes
  id = "projects/${local.p}/serviceAccounts/${local.nodes_sa}"
}
import {
  to = google_project_iam_member.gke_nodes_default_role
  id = "${local.p} roles/container.defaultNodeServiceAccount serviceAccount:${local.nodes_sa}"
}
import {
  to = google_service_account.gke_app
  id = "projects/${local.p}/serviceAccounts/${local.app_sa}"
}
import {
  to = google_project_iam_member.gke_app_cloudsql_client
  id = "${local.p} roles/cloudsql.client serviceAccount:${local.app_sa}"
}
import {
  to = google_service_account_iam_member.gke_app_workload_identity
  id = "projects/${local.p}/serviceAccounts/${local.app_sa} roles/iam.workloadIdentityUser serviceAccount:${local.p}.svc.id.goog[gridpulse/gridpulse-backend]"
}

# --- GKE Autopilot (M5) ----------------------------------------------------------------
import {
  to = google_container_cluster.main
  id = "projects/${local.p}/locations/${var.region}/clusters/gridpulse-gke"
}
