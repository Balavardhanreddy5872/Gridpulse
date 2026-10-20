# shellcheck shell=bash disable=SC2034
# Shared settings for the Milestone 5 scripts (sourced, not executed).
# Builds on the Milestone 4 settings (project, region, Cloud SQL, bucket,
# secret names, helper functions step/ok/note/die/gc). Nothing here is secret.

source ../m4/config.sh

REPO_ROOT="$(cd ../.. && pwd)"
K8S_DIR="$REPO_ROOT/k8s"
EVIDENCE_DIR="$REPO_ROOT/docs/milestone5/evidence"

# GKE Autopilot cluster (regional: Google spreads nodes over the region's zones)
CLUSTER="${CLUSTER:-gridpulse-gke}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-$REGION}"
# Pod and Service IP ranges, chosen so they never overlap the default subnet
# (10.128.0.0/20) or the Cloud SQL private range (10.60.0.0/20).
POD_CIDR="${POD_CIDR:-10.64.0.0/17}"
SERVICES_CIDR="${SERVICES_CIDR:-10.68.0.0/20}"

# Identities (no keys for either)
NODE_SA_NAME="${NODE_SA_NAME:-gridpulse-gke-nodes}"   # what the nodes run as: logs, metrics, image pulls
NODE_SA_EMAIL="${NODE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
APP_SA_NAME="${APP_SA_NAME:-gridpulse-gke-app}"       # what the backend PODS run as (Workload Identity)
APP_SA_EMAIL="${APP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Kubernetes names (must match k8s/*.yaml)
NAMESPACE="${NAMESPACE:-gridpulse}"
KSA="${KSA:-gridpulse-backend}"

# Load balancer address + hostname
GKE_IP_NAME="${GKE_IP_NAME:-gridpulse-gke-ip}"
# The hostname is kept in ONE place - k8s/managed-certificate.yaml (line marked
# "# DOMAIN"). 03_static_ip_and_dns.sh <name>.duckdns.org writes it there.
DOMAIN="${DOMAIN:-$(awk '/# DOMAIN/ { print $2; exit }' "$K8S_DIR/managed-certificate.yaml")}"

IMAGE_TAG="${IMAGE_TAG:-v5}"

k() { kubectl --namespace "$NAMESPACE" "$@"; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. $2"; }
now() { date '+%H:%M:%S'; }
