# --- VPC ------------------------------------------------------------------------
# The project's auto-mode "default" network and its us-central1 subnet existed
# before GridPulse (Google creates them with every project) and are shared with
# anything else in the project, so they are referenced, not managed. GKE added
# its own secondary ranges (pods 10.64.0.0/17, services 10.68.0.0/20) to the
# subnet when the cluster was created.
data "google_compute_network" "default" {
  name = "default"
}

data "google_compute_subnetwork" "default" {
  name   = "default"
  region = var.region
}

# --- Private Services Access for Cloud SQL (Milestone 4, deploy/m4/01_network.sh) -
# A private range inside our VPC that Google uses for the Cloud SQL instance, so
# the database has a private IP (10.60.0.3) and no public IP at all.
resource "google_compute_global_address" "cloudsql_private_range" {
  name          = "gridpulse-psa-range"
  description   = "Private IP range for Cloud SQL (GridPulse Milestone 4)"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.60.0.0"
  prefix_length = 20
  network       = data.google_compute_network.default.id

  lifecycle {
    prevent_destroy = true
    # Changing any of these forces a new range. They were set once by the M4
    # script; the description in particular is cosmetic.
    ignore_changes = [description]
  }
}

resource "google_service_networking_connection" "cloudsql_peering" {
  network                 = data.google_compute_network.default.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_private_range.name]

  lifecycle {
    prevent_destroy = true
  }
}

# --- Load balancer address (Milestone 5, deploy/m5/03_static_ip_and_dns.sh) -----
# The global IP the GKE Ingress uses (annotation kubernetes.io/ingress.global-
# static-ip-name in k8s/ingress.yaml). The DuckDNS name points at it, and the
# Google-managed certificate is issued for that name - so it must never change.
resource "google_compute_global_address" "ingress" {
  name         = "gridpulse-gke-ip"
  description  = "GridPulse GKE Ingress (Milestone 5)"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [description]
  }
}
