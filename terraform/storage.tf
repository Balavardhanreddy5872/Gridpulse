# --- Uploaded infrastructure PDFs (Milestone 4, deploy/m4/04_bucket.sh) -------------
# Private: uniform bucket-level access (IAM only) and public access prevention.
resource "google_storage_bucket" "uploads" {
  name                        = "${var.project_id}-uploads"
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle {
    prevent_destroy = true
  }
}

# The backend pods upload (cannot overwrite or delete) and read back.
resource "google_storage_bucket_iam_member" "app_uploads" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectCreator"
  member = google_service_account.gke_app.member
}

resource "google_storage_bucket_iam_member" "app_reads" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.gke_app.member
}
