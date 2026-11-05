# --- Secret Manager (Milestone 4, deploy/m4/02_secrets.sh) ---------------------------
# Terraform manages the SECRETS (name, location, labels, who may read them) but
# NOT their VALUES: the passwords were generated straight into Secret Manager
# and no secret version is declared here, so no password ever enters the
# Terraform state or this repository.
resource "google_secret_manager_secret" "db_password" {
  secret_id = "gridpulse-db-password"
  labels    = { app = "gridpulse" }

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret" "db_root_password" {
  secret_id = "gridpulse-db-root-password" # 'postgres' admin - humans only, no workload can read it
  labels    = { app = "gridpulse" }

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Only the backend pods' identity may read the app's DB password - this one
# secret, nothing else.
resource "google_secret_manager_secret_iam_member" "app_reads_db_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.gke_app.member
}
