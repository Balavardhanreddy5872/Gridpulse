# GridPulse infrastructure (Terraform)

Everything the running application uses in Google Cloud is described here.
Most of it was first created with the `gcloud` scripts of Milestones 3–5
(`deploy/m4/`, `deploy/m5/`). In Milestone 6, Terraform **adopted** those live
resources through the `import` blocks in [`imports.tf`](imports.tf), so nothing
was recreated. The monitoring and CI/CD pieces are new and Terraform creates them.

```bash
./deploy/m6/01_bootstrap_state.sh   # once: state bucket, Terraform login
./deploy/m6/02_terraform.sh         # init, plan + per-resource summary, apply, plan again
terraform -chdir=terraform plan     # refresh is on by default -> "No changes"
```

State lives in `gs://gridpulse-509202-tfstate`. The bucket is private and
versioned, and the state is never committed to this repo (`.gitignore`). Alert
e-mail addresses go in `notification.auto.tfvars`, which is also git-ignored (see
the `.example` file next to it).

## What Terraform manages

| File | Resources | Origin |
|---|---|---|
| `apis.tf` | the 13 Google APIs the app needs | M2–M6 |
| `network.tf` | Cloud SQL private range `gridpulse-psa-range` (10.60.0.0/20) + VPC peering; global IP `gridpulse-gke-ip` of the load balancer | M4, M5 (imported) |
| `database.tf` | Cloud SQL `gridpulse-db` (PostgreSQL 16, **private IP only**, TLS required, backups), database `gridpulse`, user `gridpulse` | M4 (imported) |
| `secrets.tf` | secrets `gridpulse-db-password`, `gridpulse-db-root-password` + who may read them | M4 (imported) |
| `storage.tf` | bucket `gridpulse-509202-uploads` (uniform access, public access prevention) + the pods' object roles | M4 (imported) |
| `registry.tf` | Artifact Registry `gridpulse` + cleanup policy, pull/push permissions | M3 (imported), M6 |
| `iam.tf` | service accounts `gridpulse-gke-nodes`, `gridpulse-gke-app`, their least-privilege roles, Workload Identity binding | M5 (imported) |
| `gke.tf` | GKE Autopilot cluster `gridpulse-gke` | M5 (imported) |
| `cicd.tf` | Workload Identity Federation pool + GitHub OIDC provider, `gridpulse-ci-deployer` service account + its 3 roles | **M6** |
| `monitoring.tf` | log-based metric `gridpulse_http_5xx`, e-mail notification channels, 3 alert policies, HTTPS uptime check, dashboard | **M6** |

Every adopted resource has `prevent_destroy = true`, so if a plan would
delete or replace one, Terraform stops with an error and applies nothing.
`ignore_changes` is used only for values that **Google itself sets or changes**,
such as Autopilot node settings, Cloud SQL maintenance windows and automatic disk
growth. That way `terraform plan` reports real drift instead of noise.

## What Terraform does not manage, and why

| Not in Terraform | Why | Managed by |
|---|---|---|
| **Kubernetes objects**: Deployments, Services, Ingress, HPAs, PDBs, ManagedCertificate, BackendConfig/FrontendConfig, ConfigMap | These are the *application release*. The pipeline changes them on every push and rolls them back with `kubectl rollout undo`. If Terraform owned them too, every deploy would show up as drift and the two tools would fight. | `k8s/` + `.github/workflows/deploy.yml` |
| **Load balancer internals**: forwarding rules, URL maps, backend services, NEGs, health checks, firewall rules for health checks, the Google-managed certificate `mcrt-…` | The GKE Ingress controller creates them from `k8s/ingress.yaml` and owns them. Terraform does own the static IP they use. | GKE Ingress controller |
| **Secret values** (secret versions) | Generated straight into Secret Manager (`deploy/m4/02_secrets.sh`). Declaring them would copy the passwords into the Terraform state. | Secret Manager |
| **Terraform state bucket** `gridpulse-509202-tfstate` | Terraform can't create the bucket that holds its own state. | `deploy/m6/01_bootstrap_state.sh` |
| **DNS record** `gridpulse-9.duckdns.org` | DuckDNS is outside Google Cloud and has no official Terraform provider. Terraform outputs the IP it must point at (`ingress_ip`). | duckdns.org (`deploy/m5/03_static_ip_and_dns.sh`) |
| **Billing budget** ($50/month, alerts at 10/20/25/50/100 %) | It belongs to the billing account, not the project. It was created in Milestone 2 *before* any resource, as the course required, and is unchanged. | Cloud Billing console |
| **Default VPC `default`** and its `us-central1` subnet | Google creates these with every project. Terraform references them as data sources. | Google (project default) |
| **Legacy M2–M4 VM stack**: `gridpulse-vm` (stopped), its IP `gridpulse-ip`, firewall `gridpulse-team-access`, `gridpulse-vm-sa` | Retired in Milestone 5 and not part of the running application. It's kept stopped only as a fallback and will be deleted after the course. | — |
| **Google-managed service agents** and default service accounts | Google owns them. | Google |
