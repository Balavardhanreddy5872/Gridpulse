# --- GKE Autopilot cluster (Milestone 5, deploy/m5/01_cluster.sh) -----------------
# Regional (nodes spread over us-central1's zones), in the same VPC as Cloud SQL
# so the pods reach its private IP. Google runs the nodes; we only describe pods.
#
# What runs INSIDE the cluster (Deployments, Services, Ingress, HPA, PDB, the
# managed certificate ...) is not Terraform's job: it lives in k8s/ and is
# rolled out - and rolled back - by the CI/CD pipeline (.github/workflows/deploy.yml).
resource "google_container_cluster" "main" {
  name             = "gridpulse-gke"
  location         = var.region
  enable_autopilot = true

  network    = data.google_compute_network.default.id
  subnetwork = data.google_compute_subnetwork.default.id

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.64.0.0/17" # pods
    services_ipv4_cidr_block = "10.68.0.0/20" # Services
  }

  release_channel {
    channel = "REGULAR"
  }

  # Pods authenticate as Google service accounts without keys (iam.tf).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Nodes run as gridpulse-gke-nodes instead of the default compute service
  # account (which has Editor on the whole project).
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  resource_labels = {
    app       = "gridpulse"
    milestone = "m5"
  }

  deletion_protection = true

  lifecycle {
    prevent_destroy = true
    # Autopilot owns these: Google fills in node, autoscaling, maintenance and
    # security defaults itself and changes some of them during automatic
    # upgrades. Terraform tracks what we chose (network, IP ranges, release
    # channel, Workload Identity, node identity at creation, labels) and
    # leaves Google's side alone, so `terraform plan` shows real drift only.
    ignore_changes = [
      cluster_autoscaling,
      node_config,
      node_pool,
      node_pool_defaults,
      binary_authorization,
      maintenance_policy,
      in_transit_encryption_config,
      network_performance_config,
      user_managed_keys_config,
      dataplane_optimization_mode,
      enable_cilium_clusterwide_network_policy,
      enable_fqdn_network_policy,
      enable_multi_networking,
    ]
  }

  depends_on = [google_project_service.enabled]
}
