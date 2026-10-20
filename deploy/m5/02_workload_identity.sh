#!/usr/bin/env bash
# LAPTOP, step 2: the identity the backend PODS use - Workload Identity.
#
# The Kubernetes service account gridpulse/gridpulse-backend (k8s/serviceaccount.yaml)
# is allowed to act as the Google service account gridpulse-gke-app, which gets
# the same least-privilege grants the Milestone 4 VM had:
#
#   role                                  on                          why
#   roles/cloudsql.client                 project                     look up the private IP
#   roles/secretmanager.secretAccessor    gridpulse-db-password only  read the app's DB password
#   roles/storage.objectCreator           bucket only                 upload PDFs (no overwrite/delete)
#   roles/storage.objectViewer            bucket only                 read PDFs back
#
# Image pulls are done by the NODES (gridpulse-gke-nodes), so the app identity
# does not need Artifact Registry access. No key is ever created.
#
#   ./deploy/m5/02_workload_identity.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
MEMBER="serviceAccount:${APP_SA_EMAIL}"
POOL="${PROJECT_ID}.svc.id.goog"

step "Workload Identity is on for '$CLUSTER'"
WI="$(gc container clusters describe "$CLUSTER" --location "$CLUSTER_LOCATION" --format='value(workloadIdentityConfig.workloadPool)')"
[ "$WI" = "$POOL" ] || die "workload pool is '$WI', expected '$POOL' (Autopilot enables it by default - is this the right cluster?)"
ok "workload pool $WI"

step "Google service account $APP_SA_EMAIL"
if gc iam service-accounts describe "$APP_SA_EMAIL" >/dev/null 2>&1; then
  ok "already exists"
else
  gc iam service-accounts create "$APP_SA_NAME" \
    --display-name="GridPulse backend on GKE" \
    --description="Identity of the backend pods (Workload Identity): Cloud SQL lookup, DB secret, upload bucket. No keys."
  ok "created"
  sleep 10
fi

step "Least-privilege grants"
for role in roles/storage.objectCreator roles/storage.objectViewer; do
  gc storage buckets add-iam-policy-binding "gs://$BUCKET" --member="$MEMBER" --role="$role" >/dev/null
  ok "$role  on gs://$BUCKET"
done
gc secrets add-iam-policy-binding "$SECRET_DB_PASSWORD" --member="$MEMBER" \
  --role=roles/secretmanager.secretAccessor >/dev/null
ok "roles/secretmanager.secretAccessor  on secret $SECRET_DB_PASSWORD"
gc projects add-iam-policy-binding "$PROJECT_ID" --member="$MEMBER" \
  --role=roles/cloudsql.client --condition=None >/dev/null
ok "roles/cloudsql.client  on project $PROJECT_ID"

step "Let ONLY the Kubernetes service account $NAMESPACE/$KSA act as it"
gc iam service-accounts add-iam-policy-binding "$APP_SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:${POOL}[${NAMESPACE}/${KSA}]" >/dev/null
ok "roles/iam.workloadIdentityUser  for ${POOL}[${NAMESPACE}/${KSA}]"

step "User-managed keys (must be none)"
for sa in "$APP_SA_EMAIL" "$NODE_SA_EMAIL"; do
  n="$(gc iam service-accounts keys list --iam-account="$sa" --managed-by=user --format='value(name)' | wc -l | tr -d ' ')"
  [ "$n" = "0" ] && ok "$sa: 0 keys" || die "$sa has $n user-managed key(s) - delete them"
done

echo
echo "Next: ./deploy/m5/03_static_ip_and_dns.sh <your-name>.duckdns.org"
