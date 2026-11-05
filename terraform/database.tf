# --- Cloud SQL for PostgreSQL 16 (Milestone 4, deploy/m4/03_cloudsql.sh) ----------
# PRIVATE IP ONLY (ipv4_enabled = false: no public address at all), TLS required,
# daily backups. The admin ('postgres') password was generated straight into
# Secret Manager and set at creation time; it is not in Terraform.
resource "google_sql_database_instance" "main" {
  name                = "gridpulse-db"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = true # Terraform refuses to delete it ...

  settings {
    tier                        = "db-f1-micro"
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = 10
    disk_autoresize             = true
    deletion_protection_enabled = true # ... and so does Google (protects against console / gcloud deletes)
    enable_dataplex_integration = true # on for this instance (Google's default); keeps the catalog metadata

    location_preference {
      zone = var.zone
    }

    ip_configuration {
      ipv4_enabled    = false # no public IP
      private_network = data.google_compute_network.default.id
      ssl_mode        = "ENCRYPTED_ONLY" # unencrypted connections are refused
    }

    backup_configuration {
      enabled    = true
      start_time = "08:00" # UTC
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
    # Set or changed by Google (disk growth, maintenance schedule, PITR log
    # retention, final-backup and password-policy defaults), not chosen by us.
    ignore_changes = [
      settings[0].disk_size, # grows by itself (disk_autoresize); Terraform must never try to shrink it
      settings[0].maintenance_window,
      settings[0].backup_configuration[0].point_in_time_recovery_enabled,
      settings[0].backup_configuration[0].transaction_log_retention_days,
      settings[0].final_backup_config,
      settings[0].password_validation_policy,
    ]
  }

  depends_on = [google_service_networking_connection.cloudsql_peering]
}

resource "google_sql_database" "app" {
  name     = "gridpulse"
  instance = google_sql_database_instance.main.name

  lifecycle {
    prevent_destroy = true
  }
}

# The app's database user. Its password lives ONLY in Secret Manager
# (gridpulse-db-password); deploy/m4/03_cloudsql.sh set it from there. Terraform
# never sees it, so it is never written to the Terraform state.
resource "google_sql_user" "app" {
  name     = "gridpulse"
  instance = google_sql_database_instance.main.name

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password, password_policy, type]
  }
}
