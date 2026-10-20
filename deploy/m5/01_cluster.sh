#!/usr/bin/env bash
# LAPTOP, step 1: a GKE Autopilot cluster in the same VPC as Cloud SQL.
#
# Autopilot = Google runs the nodes; we only describe pods. It is regional, so
# replicas can sit in different zones, and it is billed per pod resource
# request (plus one free cluster management fee per billing account).
#
# The nodes run as a dedicated service account with only the GKE node role and
# read access to our Artifact Registry repo (the default one has Editor).
#
#   ./deploy/m5/01_cluster.sh            (~10 minutes, mostly waiting)
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

need gcloud "https://cloud.google.com/sdk/docs/install"
need kubectl "Install it with:  gcloud components install kubectl gke-gcloud-auth-plugin   (Homebrew gcloud: brew install kubectl)"
need gke-gcloud-auth-plugin "Install it with:  gcloud components install gke-gcloud-auth-plugin"

step "Enabling the Kubernetes Engine API"
gc services enable container.googleapis.com
ok "container.googleapis.com"

step "CPU quota (free-trial accounts are capped)"
USED_ALL=0; LIMIT_ALL=0; USED_REG=0; LIMIT_REG=0
read -r USED_ALL LIMIT_ALL < <(gc compute project-info describe --flatten=quotas \
  --filter="quotas.metric=CPUS_ALL_REGIONS" --format="value(quotas.usage,quotas.limit)" 2>/dev/null \
  | awk '{printf "%d %d\n", $1, $2}') || true
read -r USED_REG LIMIT_REG < <(gc compute regions describe "$REGION" --flatten=quotas \
  --filter="quotas.metric=CPUS" --format="value(quotas.usage,quotas.limit)" 2>/dev/null \
  | awk '{printf "%d %d\n", $1, $2}') || true
note "all regions: ${USED_ALL:-?} of ${LIMIT_ALL:-?} vCPUs in use;  $REGION: ${USED_REG:-?} of ${LIMIT_REG:-?}"
if { [ "${LIMIT_ALL:-0}" -gt 0 ] && [ $((LIMIT_ALL - USED_ALL)) -lt 6 ]; } || \
   { [ "${LIMIT_REG:-0}" -gt 0 ] && [ $((LIMIT_REG - USED_REG)) -lt 6 ]; }; then
  note "Less than 6 vCPUs free. Autopilot nodes count against this quota; if pods stay Pending"
  note "with a quota error later, stop the Milestone 4 VM:  ./deploy/m5/retire_vm.sh"
else
  ok "enough headroom for the cluster's nodes"
fi

step "Finding the VPC network the VM and Cloud SQL use"
NETWORK="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].network.basename())' 2>/dev/null || echo default)"
SUBNET="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].subnetwork.basename())' 2>/dev/null || echo default)"
ok "network '$NETWORK', subnet '$SUBNET'"

step "Node service account $NODE_SA_EMAIL"
if gc iam service-accounts describe "$NODE_SA_EMAIL" >/dev/null 2>&1; then
  ok "already exists"
else
  gc iam service-accounts create "$NODE_SA_NAME" \
    --display-name="GridPulse GKE nodes" \
    --description="Identity of the GKE Autopilot nodes: logging, monitoring, image pulls. No keys."
  ok "created"
  sleep 10
fi
gc projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$NODE_SA_EMAIL" \
  --role=roles/container.defaultNodeServiceAccount --condition=None >/dev/null
ok "roles/container.defaultNodeServiceAccount (project)"
gc artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
  --member="serviceAccount:$NODE_SA_EMAIL" --role=roles/artifactregistry.reader >/dev/null
ok "roles/artifactregistry.reader (repo '$AR_REPO' only)"

step "Autopilot cluster '$CLUSTER' in $CLUSTER_LOCATION"
if gc container clusters describe "$CLUSTER" --location "$CLUSTER_LOCATION" >/dev/null 2>&1; then
  ok "already exists"
else
  note "creating - this takes 5-10 minutes"
  gc container clusters create-auto "$CLUSTER" \
    --location "$CLUSTER_LOCATION" \
    --network "$NETWORK" --subnetwork "$SUBNET" \
    --cluster-ipv4-cidr "$POD_CIDR" --services-ipv4-cidr "$SERVICES_CIDR" \
    --service-account "$NODE_SA_EMAIL" \
    --release-channel regular \
    --labels app=gridpulse,milestone=m5
  ok "created"
fi

step "kubectl credentials"
gc container clusters get-credentials "$CLUSTER" --location "$CLUSTER_LOCATION"
kubectl cluster-info | head -1

step "Cluster summary (for slide 1)"
gc container clusters describe "$CLUSTER" --location "$CLUSTER_LOCATION" --format="table[box](
  name, autopilot.enabled:label=AUTOPILOT, location, currentMasterVersion:label=VERSION,
  network, clusterIpv4Cidr:label=POD_RANGE, servicesIpv4Cidr:label=SERVICE_RANGE,
  workloadIdentityConfig.workloadPool:label=WORKLOAD_POOL)"

echo
echo "Next: ./deploy/m5/02_workload_identity.sh"
